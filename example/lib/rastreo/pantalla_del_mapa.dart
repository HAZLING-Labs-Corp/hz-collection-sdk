/// EL MAPA DE «YO» — sólo de la app de ejemplo. Calles en gris (el MISMO estilo vectorial de la
/// consola web), tu personita, la calle completa por la que fuiste y la línea cruda del GPS encima.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:maplibre/maplibre.dart' as ml;

import '../l10n/generado/textos_de_rastreo.dart';
import 'ajustar_a_calles.dart';
import 'estilo_de_calles.dart';
import 'historial_de_recorrido.dart';

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
  StreamSubscription<Position>? _yo;
  Position? _posicion;
  Timer? _reloj;
  bool _seguir = true;
  RecorridoAjustado? _calles;
  bool _ajustando = false;
  int _ajustadoConPuntos = 0;

  static const _colorRuta = Color(0xFF3B6FD4);

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
    _yo?.cancel();
    _reloj?.cancel();
    super.dispose();
  }

  /// El punto «aquí estoy» no depende de que el rastreo haya grabado algo: mientras el mapa está
  /// abierto se escucha la posición del teléfono (primer plano, sin costo de fondo).
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

  /// Pega el recorrido a las calles: al abrir y cada 6 puntos nuevos (un pedido a la vez).
  Future<void> _ajustar() async {
    final pts = widget.historial.puntos;
    if (_ajustando || pts.length < 3 || pts.length - _ajustadoConPuntos < (_calles == null ? 1 : 6)) return;
    _ajustando = true;
    final n = pts.length;
    final r = await ajustarACalles(List.of(pts));
    _ajustando = false;
    if (!mounted) return;
    _ajustadoConPuntos = n;
    if (r != null) setState(() => _calles = r);
  }

  ml.Position? _donde() {
    final pos = _posicion;
    if (pos != null) return ml.Position(pos.longitude, pos.latitude);
    final p = widget.historial.puntos;
    return p.isEmpty ? null : ml.Position(p.last.lon, p.last.lat);
  }

  void _centrarSiSigue() {
    final d = _donde();
    if (!_seguir || d == null) return;
    _mapa?.animateCamera(center: d, nativeDuration: const Duration(milliseconds: 700));
  }

  List<ml.Position> _cruda(List<PuntoDelMapa> pts) {
    final paso = pts.length <= 1500 ? 1 : (pts.length / 1500).ceil();
    return [
      for (var i = 0; i < pts.length; i += paso) ml.Position(pts[i].lon, pts[i].lat),
      if ((pts.length - 1) % paso != 0) ml.Position(pts.last.lon, pts.last.lat),
    ];
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
    final donde = _donde();
    final centro = donde ?? ml.Position(-66.8480, 10.4969);
    final capas = <ml.Layer>[
      if (_calles != null) ...[
        ml.PolylineLayer(
          polylines: [ml.LineString(coordinates: [for (final c in _calles!.calles) ml.Position(c.longitude, c.latitude)])],
          color: _colorRuta.withValues(alpha: 0.30),
          width: 16,
        ),
        ml.PolylineLayer(
          polylines: [ml.LineString(coordinates: [for (final c in _calles!.calles) ml.Position(c.longitude, c.latitude)])],
          color: _colorRuta,
          width: 5,
        ),
      ],
      // lo medido por el GPS siempre se ve: fino, encima de la calle
      if (pts.length >= 2)
        ml.PolylineLayer(polylines: [ml.LineString(coordinates: _cruda(pts))], color: _calles != null ? const Color(0xFF1F3F86) : _colorRuta, width: _calles != null ? 2 : 4),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(t.mapaTitulo),
        actions: [
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
                        if (donde != null)
                          (widget.rastreo?.captura.estado == EstadoDeMovimiento.rodando || (_posicion?.speed ?? 0) > 1.0)
                              // rodando: la figura desde arriba, girando con el rumbo, como un navegador
                              ? ml.Marker(
                                  point: donde,
                                  size: const Size(48, 48),
                                  child: Transform.rotate(
                                    angle: ((_posicion?.heading ?? 0) < 0 ? 0 : (_posicion?.heading ?? 0)) * math.pi / 180,
                                    child: _FiguraDesdeArriba(widget.rastreo?.configuracion.medio),
                                  ),
                                )
                              : ml.Marker(
                                  point: donde,
                                  size: const Size(44, 56),
                                  child: Transform.translate(offset: const Offset(0, -26), child: _PinDelMedio(widget.rastreo?.configuracion.medio)),
                                ),
                      ]),
                    ],
                  ),
                if (ultimo == null && _posicion == null)
                  Center(child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(t.mapaSinPuntos)))),
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

/// El pin con la figura del medio que mide el perfil (dato `rastreo.medio`): persona, moto o carro —
/// las mismas siluetas que la consola web.
class _PinDelMedio extends StatelessWidget {
  const _PinDelMedio(this.medio);
  final String? medio;
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 44, height: 56, child: CustomPaint(painter: _PintorDelPin(_colorRuta, medio ?? 'pie')));
  static const _colorRuta = Color(0xFF3B6FD4);
}

class _PintorDelPin extends CustomPainter {
  const _PintorDelPin(this.color, this.medio);
  final Color color;
  final String medio;

  @override
  void paint(Canvas canvas, Size size) {
    const cx = 22.0, cy = 21.0, r = 17.0;
    final pin = Path()
      ..moveTo(cx - r * 0.81, cy + r * 0.59)
      ..arcTo(Rect.fromCircle(center: const Offset(cx, cy), radius: r), math.pi * 0.8, math.pi * 1.4, false)
      ..lineTo(cx, 53)
      ..close();
    canvas.drawShadow(pin, Colors.black, 4, true);
    canvas.drawPath(pin, Paint()..color = color);
    canvas.drawPath(pin, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5);
    final blanco = Paint()..color = Colors.white;
    final trazo = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (medio) {
      case 'dosRuedas':
      case 'bici':
        canvas.drawCircle(const Offset(cx - 8, cy + 6), 4.2, trazo);
        canvas.drawCircle(const Offset(cx + 8, cy + 6), 4.2, trazo);
        canvas.drawPath(Path()..moveTo(cx - 8, cy + 6)..lineTo(cx - 2, cy - 1)..lineTo(cx + 5, cy - 1)..lineTo(cx + 8, cy + 6), trazo);
        canvas.drawLine(const Offset(cx + 5, cy - 1), const Offset(cx + 9, cy - 6), trazo);
        canvas.drawCircle(const Offset(cx + 1, cy - 9), 3, blanco);
        canvas.drawLine(const Offset(cx + 1, cy - 6), const Offset(cx - 1, cy - 1), trazo);
      case 'carro':
      case 'bus':
        canvas.drawPath(
            Path()
              ..moveTo(cx - 13, cy + 4)..lineTo(cx - 13, cy - 1)..lineTo(cx - 8, cy - 2)..lineTo(cx - 4, cy - 8)
              ..lineTo(cx + 6, cy - 8)..lineTo(cx + 10, cy - 2)..lineTo(cx + 13, cy - 1)..lineTo(cx + 13, cy + 4)..close(),
            blanco);
        canvas.drawCircle(const Offset(cx - 7, cy + 5), 3.2, Paint()..color = color);
        canvas.drawCircle(const Offset(cx + 7, cy + 5), 3.2, Paint()..color = color);
        canvas.drawCircle(const Offset(cx - 7, cy + 5), 1.6, blanco);
        canvas.drawCircle(const Offset(cx + 7, cy + 5), 1.6, blanco);
      default:
        canvas.drawCircle(const Offset(cx, cy - 5), 5.2, blanco);
        final hombros = Path()
          ..moveTo(cx - 9.5, cy + 10)
          ..quadraticBezierTo(cx - 9.5, cy + 1.5, cx, cy + 1.5)
          ..quadraticBezierTo(cx + 9.5, cy + 1.5, cx + 9.5, cy + 10)
          ..close();
        canvas.drawPath(hombros, blanco);
    }
  }

  @override
  bool shouldRepaint(covariant _PintorDelPin old) => old.color != color || old.medio != medio;
}

/// Quien va rodando se ve DESDE ARRIBA y gira con el rumbo: el piloto en su moto (casco, hombros y la
/// moto con sus dos ruedas), el carro con su parabrisas, o la persona. Las mismas siluetas de la consola.
class _FiguraDesdeArriba extends StatelessWidget {
  const _FiguraDesdeArriba(this.medio);
  final String? medio;
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 48, height: 48, child: CustomPaint(painter: _PintorDesdeArriba(const Color(0xFF2E9E5B), medio ?? 'pie')));
}

class _PintorDesdeArriba extends CustomPainter {
  const _PintorDesdeArriba(this.color, this.medio);
  final Color color;
  final String medio;

  RRect _r(double x, double y, double w, double h, double r) => RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));

  @override
  void paint(Canvas canvas, Size size) {
    const cx = 24.0, cy = 24.0;
    final disco = Path()..addOval(Rect.fromCircle(center: const Offset(cx, cy), radius: 19));
    canvas.drawShadow(disco, Colors.black, 4, true);
    canvas.drawPath(disco, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(cx, cy), 19, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 3);
    final tinta = Paint()..color = color;
    final blanco = Paint()..color = Colors.white;
    final trazo = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round;
    switch (medio) {
      case 'dosRuedas':
      case 'bici':
        canvas.drawRRect(_r(cx - 3.5, cy - 15, 7, 30, 3.5), tinta);
        canvas.drawRRect(_r(cx - 1.6, cy - 14, 3.2, 6, 1.6), blanco);
        canvas.drawRRect(_r(cx - 1.6, cy + 8, 3.2, 6, 1.6), blanco);
        canvas.drawLine(const Offset(cx - 9, cy - 3), const Offset(cx + 9, cy - 3), trazo);
        canvas.drawOval(Rect.fromCenter(center: const Offset(cx, cy + 2), width: 15, height: 10), tinta);
        canvas.drawCircle(const Offset(cx, cy - 1), 4.2, blanco);
        canvas.drawCircle(const Offset(cx, cy - 1), 2.8, tinta);
      case 'carro':
      case 'bus':
        canvas.drawRRect(_r(cx - 8, cy - 15, 16, 30, 5), tinta);
        canvas.drawRRect(_r(cx - 6, cy - 9, 12, 5, 2), blanco);
        canvas.drawRRect(_r(cx - 6, cy + 6, 12, 4, 2), blanco);
      default:
        canvas.drawOval(Rect.fromCenter(center: const Offset(cx, cy + 3), width: 20, height: 11), tinta);
        canvas.drawCircle(const Offset(cx, cy - 4), 5, blanco);
        canvas.drawCircle(const Offset(cx, cy - 4), 3.4, tinta);
    }
  }

  @override
  bool shouldRepaint(covariant _PintorDesdeArriba old) => old.color != color || old.medio != medio;
}
