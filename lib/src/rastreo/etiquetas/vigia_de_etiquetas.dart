/// EL VIGÍA DE LAS ETIQUETAS — abre ventanas cortas de escaneo MIENTRAS RUEDA y guarda lo que oye.
///
/// Batería: nunca escaneo continuo. Cada `cadaSeg` (30 s por omisión) se pregunta si el aparato
/// está rodando y si hay etiquetas que escuchar; si sí, escucha `escaneoSeg` (8 s) y corta. De cada
/// ventana sale, por etiqueta configurada, UN avistamiento: el de más señal, con su hora. Detenido
/// (GPS apagado) no se escanea: el servidor sólo pregunta por la etiqueta en los tramos rodando.
///
/// Lo que se oyó espera en memoria (techo [techo]) hasta que el emisor arma el lote siguiente
/// ([tomarHasta]), y entra al cuerpo firmado. Si la app muere, lo no mandado se pierde: es dato
/// informativo y la ruta no depende de él.
library;

import 'dart:async';

import 'escaner_ble.dart';
import 'etiquetas_ble.dart';

class VigiaDeEtiquetas {
  VigiaDeEtiquetas({
    required this.escaner,
    required this.configuracion,
    required this.rodando,
    DateTime Function()? ahora,
    this.alProblema,
  }) : _ahora = ahora ?? DateTime.now;

  final EscanerBle escaner;
  final ConfiguracionDeEtiquetas Function() configuracion;
  final bool Function() rodando;
  final void Function(String)? alProblema;
  final DateTime Function() _ahora;

  /// Techo de avistamientos en espera (el de la ingesta por lote es 400).
  static const techo = 400;

  final List<Avistamiento> _pendientes = [];
  Timer? _reloj;
  StreamSubscription<AnuncioBle>? _escucha;
  Timer? _corte;
  int _ventanas = 0;
  int _oidos = 0;

  int get ventanas => _ventanas;
  int get oidos => _oidos;
  int get pendientes => _pendientes.length;
  bool get escuchando => _escucha != null;

  /// Arranca el reloj. Cada tic decide si abrir una ventana; el período se relee de la config.
  void iniciar() {
    if (_reloj != null) return;
    _programar();
  }

  void _programar() {
    _reloj = Timer(Duration(seconds: configuracion().cadaSeg), () {
      unawaited(tic());
      if (_reloj != null) _programar();
    });
  }

  /// Una vuelta: si toca, abre una ventana. Público para las pruebas.
  Future<void> tic() async {
    final c = configuracion();
    if (!c.hayQueEscuchar || !rodando() || _escucha != null) return;
    await ventana(c);
  }

  /// Escucha `escaneoSeg` y deja un avistamiento por etiqueta (el de más señal).
  Future<void> ventana(ConfiguracionDeEtiquetas c) {
    // la propia gana si la misma huella también estuviera en búsqueda (no debería: el servidor la saca)
    final enBusqueda = {for (final e in c.busqueda) identificadorDe(e): e.etiquetaId};
    final porHuella = {for (final e in c.lista) identificadorDe(e): e.etiquetaId};
    final mejor = <String, Avistamiento>{};
    final listo = Completer<void>();
    void cerrar() {
      _corte?.cancel();
      _corte = null;
      final s = _escucha;
      _escucha = null;
      unawaited(s?.cancel());
      for (final a in mejor.values) {
        if (_pendientes.length >= techo) _pendientes.removeAt(0);
        _pendientes.add(a);
        _oidos++;
      }
      if (!listo.isCompleted) listo.complete();
    }

    _ventanas++;
    try {
      _escucha = escaner.escuchar().listen((a) {
        if (a.rssi < c.rssiMin) return;
        final h = identificadorDelAnuncio(a);
        if (h == null) return;
        final propia = porHuella[h];
        final ajena = propia == null ? enBusqueda[h] : null;
        final clave = propia ?? (ajena == null ? null : 'bq:$ajena');
        if (clave == null) return;
        final previo = mejor[clave];
        if (previo == null || a.rssi > previo.rssi) {
          final t = _ahora().millisecondsSinceEpoch;
          mejor[clave] = propia != null ? Avistamiento(t: t, etiquetaId: propia, rssi: a.rssi) : Avistamiento(t: t, busquedaId: ajena, rssi: a.rssi);
        }
      }, onError: (Object e) {
        alProblema?.call('etiquetas: el escaneo BLE falló ($e)');
        cerrar();
      }, onDone: cerrar);
    } catch (e) {
      alProblema?.call('etiquetas: no se pudo escanear ($e)');
      cerrar();
      return listo.future;
    }
    _corte = Timer(Duration(seconds: c.escaneoSeg), cerrar);
    return listo.future;
  }

  /// Saca y devuelve lo oído hasta [tMs] inclusive (para el lote que se arma ahora).
  List<Avistamiento> tomarHasta(int tMs) {
    final out = _pendientes.where((a) => a.t <= tMs).toList();
    _pendientes.removeWhere((a) => a.t <= tMs);
    return out;
  }

  Future<void> detener() async {
    _reloj?.cancel();
    _reloj = null;
    _corte?.cancel();
    _corte = null;
    await _escucha?.cancel();
    _escucha = null;
  }
}
