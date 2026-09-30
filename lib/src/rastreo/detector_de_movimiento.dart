/// EL DETECTOR DE MOVIMIENTO DE LA CAPTURA PROPIA — puro: recibe lecturas, actividades y
/// el paso del tiempo, y devuelve qué hacer. No toca el GPS, ni la red, ni el disco; por
/// eso se prueba entero sin un teléfono, que es justo la parte que más cuesta probar en la
/// calle.
///
/// ══ LOS TRES ESTADOS ══
///
/// ```
///   QUIETO ──(salió de la zona · o la actividad dice vehículo/bici/a pie · o ya va rápido)──► CONFIRMANDO
///   CONFIRMANDO ──(2 lecturas seguidas a más de arranqueKmh)──► RODANDO
///   CONFIRMANDO ──(3 min sin confirmar)──► QUIETO           (el GPS saltó, o fue al baño)
///   RODANDO ──(quietoMin sin moverse, o sin lecturas)──► QUIETO   (se apaga el GPS preciso)
/// ```
///
/// En QUIETO el GPS preciso está APAGADO: se escucha una lectura de bajo consumo (antenas y
/// wifi, cada 100 m) que sólo sirve para notar que salió de la zona. En CONFIRMANDO y
/// RODANDO está prendido. **Sólo se graba en RODANDO.**
///
/// ══ 🔴 LA VELOCIDAD SE CONFIRMA; NO SE LE CREE A UNA SOLA LECTURA ══
///
/// Un GPS barato dentro de un edificio da saltos de 80 m en un segundo: 288 km/h. Si una
/// lectura bastara, un teléfono en una mesa «arrancaría» veinte veces al día y cada vez
/// prendería el GPS tres minutos. Se piden dos seguidas, con precisión razonable.
///
/// ══ EL RITMO LO PONE LA TABLA DE CADENCIA ══
///
/// En cada entrada el detector arma la [SituacionDelAparato] (forzado, velocidad, si rueda,
/// minutos quieto, hora local) y elige la fila de `cadencia` (ver `cadencia.dart`). La fila
/// dice cada cuánto se graba (`muestreoSeg`; 0 = no se graba) y cada cuánto sale un lote.
/// El GPS preciso se abre al muestreo más corto de la tabla y el detector descarta lecturas
/// para cumplir el de la fila: así cruzar los 40 km/h no reabre el flujo.
///
/// ══ LA VELOCIDAD DERIVADA ══
///
/// Si el sistema no da velocidad (`v < 0`: pasa con fijaciones de red, y en iPhone sin
/// GPS), se deriva de la distancia a la lectura anterior sobre el tiempo. Se usa para
/// DECIDIR; el punto guardado lleva la del sistema si la hay, o la derivada si no.
library;

import 'dart:math' as math;

import 'cadencia.dart';
import 'configuracion_de_rastreo.dart';

enum EstadoDeMovimiento { quieto, confirmando, rodando }

/// La actividad que informa el sistema (Activity Recognition / CoreMotion), ya traducida.
enum TipoDeActividad { vehiculo, bici, aPie, corriendo, quieto, desconocida }

/// Una lectura de ubicación, venga del GPS preciso o de la de bajo consumo.
class Lectura {
  const Lectura({
    required this.t,
    required this.lat,
    required this.lon,
    required this.acc,
    required this.v,
    this.h = 0,
    this.alt = 0,
    this.mock = false,
  });

  final int t;
  final double lat;
  final double lon;
  final double acc;

  /// m/s, o negativo si el sistema no la sabe.
  final double v;
  final double h;
  final double alt;
  final bool mock;
}

/// Qué tiene que hacer la captura después de una entrada.
class Decision {
  const Decision({
    required this.estado,
    required this.gpsPreciso,
    this.grabar = false,
    this.velocidad = 0,
    this.intervalo = const Duration(seconds: 10),
    this.fila = FilaDeCadencia.respaldo,
    this.cambio = false,
    this.cambioDeFila = false,
    this.vaciar = false,
    this.hueco,
    this.motivo,
  });

  final EstadoDeMovimiento estado;

  /// Si el GPS preciso tiene que estar prendido.
  final bool gpsPreciso;

  /// Si esta lectura se guarda como punto.
  final bool grabar;

  /// La velocidad que se guarda con el punto (m/s).
  final double velocidad;

  /// Cada cuánto se graba ahora (el `muestreoSeg` de la fila; cero = no se graba).
  final Duration intervalo;

  /// La fila de cadencia que manda ahora.
  final FilaDeCadencia fila;

  /// Si el estado cambió con esta entrada.
  final bool cambio;

  /// Si la fila de cadencia cambió con esta entrada (p. ej. de «rodando» a «rapido»).
  final bool cambioDeFila;

  /// Si hay que mandar lo que espere (se detuvo).
  final bool vaciar;

  /// Si entre esta lectura y la anterior grabada hubo un hueco: (desde, hasta).
  final (int, int)? hueco;

  /// Por qué cambió, en castellano, para el diagnóstico.
  final String? motivo;
}

class DetectorDeMovimiento {
  DetectorDeMovimiento(this._config);

  ConfiguracionDeRastreo _config;
  set config(ConfiguracionDeRastreo c) => _config = c;

  /// Radio de la zona de reposo. 150 m: más que el error de una fijación por antenas en
  /// ciudad (~100 m), menos que una cuadra y media.
  static const radioDeZonaM = 150.0;

  /// Moverse es ir a más de esto, o alejarse [radioDeReposoM] del último punto de reposo.
  static const velocidadDeMovimientoMs = 1.0; // 3,6 km/h
  static const radioDeReposoM = 50.0;

  /// Una lectura con peor precisión no confirma nada.
  static const precisionParaConfirmarM = 50.0;

  static const esperaDeConfirmacion = Duration(minutes: 3);

  EstadoDeMovimiento estado = EstadoDeMovimiento.quieto;
  int tramo = 0;

  Lectura? _ancla; // centro de la zona de reposo (en QUIETO)
  Lectura? _anterior; // la última lectura precisa
  Lectura? _reposo; // en RODANDO: dónde empezó a no moverse
  int _confirmaciones = 0;
  int? _desdeConfirmando;
  int? _ultimoMovimiento;
  int? _ultimaGrabada;
  int? _ultimaLectura;
  double _ultimaVelMs = 0;
  int? _quietoDesde;
  FilaDeCadencia fila = FilaDeCadencia.respaldo;

  Duration get intervalo => Duration(seconds: fila.muestreoSeg);

  /// El umbral para decir que hubo un hueco en RODANDO: cuatro intervalos, y nunca menos
  /// de un minuto (un túnel corto no es un hueco del SDK).
  Duration get umbralDeHueco {
    final seg = fila.muestreoSeg > 0 ? fila.muestreoSeg : FilaDeCadencia.respaldo.muestreoSeg;
    final cuatro = Duration(seconds: seg * 4);
    return cuatro < const Duration(minutes: 1) ? const Duration(minutes: 1) : cuatro;
  }

  /// La situación del aparato en [t], para la tabla.
  SituacionDelAparato situacion(int t) => SituacionDelAparato(
        forzado: _config.estadoForzado != null,
        velKmh: _ultimaVelMs * 3.6,
        enMovimiento: estado == EstadoDeMovimiento.rodando,
        quietoMin: estado == EstadoDeMovimiento.rodando
            ? 0
            : (t - (_quietoDesde ?? t)) / 60000,
        hora: DateTime.fromMillisecondsSinceEpoch(t),
      );

  /// Reevalúa la tabla. Devuelve si la fila cambió.
  bool _evaluar(int t) {
    final nueva = _config.filaPara(situacion(t));
    final cambio = !identical(nueva, fila) && nueva.estado != fila.estado;
    fila = nueva;
    return cambio;
  }

  bool _filaCambio = false;

  Decision _decision({
    bool grabar = false,
    double velocidad = 0,
    bool cambio = false,
    bool vaciar = false,
    (int, int)? hueco,
    String? motivo,
  }) =>
      Decision(
        estado: estado,
        gpsPreciso: estado != EstadoDeMovimiento.quieto,
        grabar: grabar,
        velocidad: velocidad,
        intervalo: intervalo,
        fila: fila,
        cambio: cambio,
        cambioDeFila: _filaCambio,
        vaciar: vaciar,
        hueco: hueco,
        motivo: motivo,
      );

  /// Una lectura. [precisa] dice si vino del GPS preciso (en QUIETO llegan las de bajo
  /// consumo).
  Decision lectura(Lectura l, {required bool precisa}) {
    _ultimaLectura = l.t;
    final ant = _anterior;
    final vDerivada = (ant != null && l.t > ant.t)
        ? _distancia(ant, l) / ((l.t - ant.t) / 1000)
        : -1.0;
    final v = l.v >= 0 ? l.v : vDerivada;
    if (precisa) _anterior = l;
    if (precisa && v >= 0) _ultimaVelMs = v;
    _quietoDesde ??= l.t;
    _filaCambio = _evaluar(l.t);

    switch (estado) {
      case EstadoDeMovimiento.quieto:
        final ancla = _ancla;
        if (ancla == null) {
          _ancla = l;
          return _decision();
        }
        final lejos = _distancia(ancla, l) > radioDeZonaM && l.acc < 200;
        final rapido = l.v >= _config.arranqueMs;
        if (lejos || rapido) {
          return _aConfirmando(l.t, lejos ? 'salió de la zona' : 'va a más de ${_config.arranqueKmh} km/h');
        }
        return _decision();

      case EstadoDeMovimiento.confirmando:
        if (!precisa) return _decision();
        if (v >= _config.arranqueMs && l.acc <= precisionParaConfirmarM) {
          _confirmaciones++;
        } else {
          _confirmaciones = 0;
        }
        if (_confirmaciones >= 2) {
          estado = EstadoDeMovimiento.rodando;
          tramo++;
          _ultimoMovimiento = l.t;
          _reposo = l;
          _ultimaGrabada = l.t;
          _filaCambio = _evaluar(l.t) || _filaCambio;
          if (fila.muestreoSeg <= 0) {
            return _decision(cambio: true, motivo: 'confirmado, pero la fila ${fila.estado} no graba');
          }
          return _decision(
              grabar: true,
              velocidad: v < 0 ? 0 : v,
              cambio: true,
              motivo: 'confirmado: ${(v * 3.6).toStringAsFixed(0)} km/h dos veces');
        }
        if (l.t - (_desdeConfirmando ?? l.t) > esperaDeConfirmacion.inMilliseconds) {
          return _aQuieto(l, 'no se confirmó en ${esperaDeConfirmacion.inMinutes} min',
              vaciar: false);
        }
        return _decision();

      case EstadoDeMovimiento.rodando:
        if (!precisa) return _decision();
        final reposo = _reposo ?? l;
        if (v >= velocidadDeMovimientoMs || _distancia(reposo, l) > radioDeReposoM) {
          _ultimoMovimiento = l.t;
          _reposo = l;
        }
        if (l.t - (_ultimoMovimiento ?? l.t) >= _config.quieto.inMilliseconds) {
          return _aQuieto(l, 'quieto ${_config.quietoMin} min', vaciar: true);
        }
        if (fila.muestreoSeg <= 0) return _decision();
        final ultima = _ultimaGrabada;
        // Medio segundo de tolerancia: Android entrega «cada 10 s» a veces a los 9,8.
        if (ultima != null && l.t - ultima < intervalo.inMilliseconds - 500) {
          return _decision();
        }
        (int, int)? hueco;
        if (ultima != null && l.t - ultima > umbralDeHueco.inMilliseconds) {
          hueco = (ultima, l.t);
        }
        _ultimaGrabada = l.t;
        return _decision(grabar: true, velocidad: v < 0 ? 0 : v, hueco: hueco);
    }
  }

  /// Lo que informa el reconocimiento de actividad del sistema.
  Decision actividad(TipoDeActividad a, int t) {
    _filaCambio = false;
    if (estado == EstadoDeMovimiento.quieto &&
        (a == TipoDeActividad.vehiculo ||
            a == TipoDeActividad.bici ||
            a == TipoDeActividad.corriendo ||
            a == TipoDeActividad.aPie)) {
      return _aConfirmando(t, 'la actividad dice ${a.name}');
    }
    return _decision();
  }

  /// El paso del tiempo, para lo que se decide sin lecturas: un GPS que dejó de entregar
  /// mientras rodaba (un sótano) o una confirmación que no llega.
  Decision tic(int t) {
    _quietoDesde ??= t;
    _filaCambio = _evaluar(t);
    final ultima = _ultimaLectura;
    if (estado == EstadoDeMovimiento.rodando && ultima != null &&
        t - (_ultimoMovimiento ?? ultima) >= _config.quieto.inMilliseconds) {
      return _aQuieto(_anterior, 'sin moverse ni leer ${_config.quietoMin} min', vaciar: true);
    }
    if (estado == EstadoDeMovimiento.confirmando &&
        t - (_desdeConfirmando ?? t) > esperaDeConfirmacion.inMilliseconds) {
      return _aQuieto(_anterior, 'no se confirmó en ${esperaDeConfirmacion.inMinutes} min',
          vaciar: false);
    }
    return _decision();
  }

  Decision _aConfirmando(int t, String motivo) {
    estado = EstadoDeMovimiento.confirmando;
    _confirmaciones = 0;
    _desdeConfirmando = t;
    return _decision(cambio: true, motivo: motivo);
  }

  Decision _aQuieto(Lectura? l, String motivo, {required bool vaciar}) {
    estado = EstadoDeMovimiento.quieto;
    _ancla = l ?? _ancla;
    _confirmaciones = 0;
    _desdeConfirmando = null;
    _reposo = null;
    _ultimaGrabada = null;
    _ultimaVelMs = 0;
    // Quieto desde el último movimiento, no desde ahora: quien se detuvo hace 5 min lleva
    // 5 min quieto, no 0.
    _quietoDesde = _ultimoMovimiento ?? l?.t ?? _quietoDesde;
    _ultimoMovimiento = null;
    _filaCambio = _evaluar(l?.t ?? _quietoDesde ?? 0) || _filaCambio;
    return _decision(cambio: true, vaciar: vaciar, motivo: motivo);
  }

  /// Haversine, metros.
  static double _distancia(Lectura a, Lectura b) {
    const r = 6371000.0;
    final dLat = _rad(b.lat - a.lat);
    final dLon = _rad(b.lon - a.lon);
    final x = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(x)));
  }

  static double distanciaM(double lat1, double lon1, double lat2, double lon2) => _distancia(
      Lectura(t: 0, lat: lat1, lon: lon1, acc: 0, v: 0),
      Lectura(t: 0, lat: lat2, lon: lon2, acc: 0, v: 0));

  static double _rad(double g) => g * math.pi / 180;
}
