/// LAS CAPTURAS — quién le da al rastreo los puntos. Dos, conmutables por una bandera.
///
/// ══ POR QUÉ HAY DOS (D-04) ══
///
/// La **propia** ([CapturaPropia]) es geolocator con su servicio en primer plano y el
/// detector de este paquete. No agrega permisos ni dependencias con licencia; su límite
/// conocido es que vive con el proceso: si el sistema o la persona matan la aplicación, deja
/// de grabar hasta que se vuelva a abrir.
///
/// La de **Transistor** (`flutter_background_geolocation`) sobrevive a eso —tiene su propio
/// servicio, su arranque sin interfaz y veinte años de trucos contra los fabricantes— pero
/// cuesta una licencia en producción e inyecta sus permisos en el manifiesto.
///
/// Cuál gana lo decide la medición en un Tecno y un Xiaomi reales, no esta página.
///
/// ══ 🔴 POR QUÉ LA DE TRANSISTOR NO VIVE EN ESTE PAQUETE ══
///
/// `flutter_background_geolocation` declara en SU manifiesto ubicación en segundo plano,
/// reconocimiento de actividad, arranque con el sistema y más. Si este SDK la importara,
/// **se los inyectaría a toda aplicación que lo instale** —las de crédito incluidas, a las
/// que la política de préstamos de Play les prohíbe la ubicación en segundo plano—. Es
/// exactamente lo que `bin/muro.dart` existe para impedir.
///
/// Por eso el SDK define la interfaz [CapturaDeRastreo] y trae la propia; la de Transistor
/// la implementa la aplicación que la quiera (la de ejemplo lo hace en
/// `example/lib/rastreo/captura_transistor.dart`). Si D-04 la elige, sale como un paquete
/// aparte, `hz_collection_rastreo_transistor`, que sólo instala quien la necesita.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'cadencia.dart';
import 'configuracion_de_rastreo.dart';
import 'detector_de_movimiento.dart';
import 'nativo_de_rastreo.dart';
import 'punto.dart';

/// Lo que una captura le cuenta al rastreo.
sealed class EventoDeCaptura {
  const EventoDeCaptura();
}

/// Un punto para grabar, del [tramo] dado (cada arranque es un tramo nuevo).
class PuntoCapturado extends EventoDeCaptura {
  const PuntoCapturado(this.punto, this.tramo, {this.hueco});
  final PuntoDeRastreo punto;
  final int tramo;

  /// Si antes de este punto hubo un hueco dentro del tramo: (desde, hasta) en ms.
  final (int, int)? hueco;
}

/// Cambió el estado de la captura.
class CambioDeEstado extends EventoDeCaptura {
  const CambioDeEstado(this.estado, this.motivo, {this.vaciar = false});
  final EstadoDeMovimiento estado;
  final String? motivo;

  /// Se detuvo: lo que espera tiene que salir ya, no dentro de cinco minutos.
  final bool vaciar;
}

/// Algo falló sin detener la captura (o deteniéndola): se muestra en el diagnóstico.
class ProblemaDeCaptura extends EventoDeCaptura {
  const ProblemaDeCaptura(this.descripcion);
  final String descripcion;
}

/// El contrato de una captura. La propia y la de Transistor lo cumplen igual.
abstract class CapturaDeRastreo {
  /// `propia` · `transistor` — lo que se muestra y lo que se anota al medir.
  String get nombre;

  /// Los puntos, los cambios de estado y los problemas.
  Stream<EventoDeCaptura> get eventos;

  EstadoDeMovimiento get estado;

  /// La fila de la tabla de cadencia que manda ahora (ver `cadencia.dart`). De acá sale
  /// cada cuánto se graba y cada cuánto sale un lote.
  FilaDeCadencia get cadencia;

  /// Si está corriendo (aunque esté en QUIETO).
  bool get activa;

  /// Arranca con esta configuración. Devuelve `null` si arrancó, o por qué no.
  Future<String?> iniciar(ConfiguracionDeRastreo config);

  /// Cambia los números sin reiniciar si se puede.
  Future<void> actualizar(ConfiguracionDeRastreo config);

  Future<void> detener();
}

/// Los textos del aviso fijo de Android mientras se mide. Son del comercio: van a estar en
/// la barra de la persona todo el día.
class TextosDelAvisoDeRastreo {
  const TextosDelAvisoDeRastreo({
    this.titulo = 'Registrando tu recorrido',
    this.cuerpo = 'Se apaga solo cuando te detienes.',
    this.canal = 'Recorrido',
  });
  final String titulo;
  final String cuerpo;
  final String canal;
}

/// LA CAPTURA PROPIA — geolocator + el detector + la actividad del sistema.
///
/// ══ 🔴 DOS FLUJOS, NUNCA A LA VEZ, Y SÓLO DOS CAMBIOS POR VIAJE ══
///
/// En QUIETO escucha una lectura de bajo consumo (sin GPS, cada 100 m). En CONFIRMANDO y
/// RODANDO, el GPS preciso al muestreo MÁS CORTO de la tabla de cadencia; el de cada fila lo
/// aplica el detector descartando lecturas. Así el flujo cambia dos veces por viaje (al
/// arrancar y al detenerse) y no cada vez que la velocidad cruza la de la fila «rápido»: en Android 12+ reabrir un servicio de ubicación
/// con la app en el fondo puede estar prohibido (salvo con la batería «Sin restricciones»,
/// que es lo que MEDIR.md pide activar), así que cada cambio de flujo es un riesgo.
class CapturaPropia implements CapturaDeRastreo {
  CapturaPropia({this.textos = const TextosDelAvisoDeRastreo(), Battery? bateria})
      : _bateria = bateria ?? Battery();

  final TextosDelAvisoDeRastreo textos;
  final Battery _bateria;

  @override
  String get nombre => 'propia';

  final _eventos = StreamController<EventoDeCaptura>.broadcast();
  @override
  Stream<EventoDeCaptura> get eventos => _eventos.stream;

  DetectorDeMovimiento? _detector;
  StreamSubscription<Position>? _flujo;
  StreamSubscription<TipoDeActividad>? _actividad;
  StreamSubscription<AccelerometerEvent>? _acel;
  double _gx = 0, _gy = 0, _gz = 0;
  int? _movDesde;
  int _ultimoMov = 0;
  Timer? _tic;
  bool? _flujoPreciso;
  bool _activa = false;
  ConfiguracionDeRastreo _config = ConfiguracionDeRastreo.apagada;

  int _nivelDeBateria = -1;
  DateTime? _bateriaLeida;

  @override
  bool get activa => _activa;

  @override
  EstadoDeMovimiento get estado => _detector?.estado ?? EstadoDeMovimiento.quieto;

  @override
  FilaDeCadencia get cadencia => _detector?.fila ?? FilaDeCadencia.respaldo;

  @override
  Future<String?> iniciar(ConfiguracionDeRastreo config) async {
    if (_activa) {
      await actualizar(config);
      return null;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'el teléfono tiene la ubicación apagada';
    }
    final p = await Geolocator.checkPermission();
    if (p != LocationPermission.always && p != LocationPermission.whileInUse) {
      return 'la aplicación no tiene permiso de ubicación';
    }
    _config = config;
    _detector = DetectorDeMovimiento(config);
    _activa = true;
    await _abrirFlujo(preciso: false);

    // La actividad es un refuerzo, no una condición: sin permiso o sin Play Services, la
    // salida de zona y la velocidad alcanzan.
    if (await ActividadDelAparato.tienePermiso()) {
      _actividad = ActividadDelAparato.flujo().listen(
        (a) => _aplicar(_detector!.actividad(a, DateTime.now().millisecondsSinceEpoch)),
        onError: (Object e) => _eventos.add(ProblemaDeCaptura('actividad: $e')),
      );
    } else {
      _eventos.add(const ProblemaDeCaptura(
          'sin permiso de actividad física: se detecta sólo por zona y velocidad'));
    }
    // CL-37 · DESPERTAR POR ACELERÓMETRO: quieto y con el GPS apagado, un teléfono que se mueve
    // `despertarSeg` segundos seguidos enciende el GPS preciso (la actividad del sistema y la
    // salida de zona llegan tarde, o no llegan sin permiso). Sólo se mira estando quieto.
    _acel = accelerometerEventStream(samplingPeriod: SensorInterval.normalInterval).listen(
      _alAcelerometro,
      onError: (Object e) => _eventos.add(ProblemaDeCaptura('acelerómetro: $e')),
    );
    // «Cada pocos segundos» (PM-025 §4.5): la tabla se reevalúa aunque no lleguen lecturas
    // —la hora cruza las 22:00, el quieto pasa de 5 a 30 min—. Es una cuenta en memoria.
    _tic = Timer.periodic(const Duration(seconds: 5),
        (_) => _aplicar(_detector!.tic(DateTime.now().millisecondsSinceEpoch)));
    _eventos.add(const CambioDeEstado(EstadoDeMovimiento.quieto, 'arrancó'));
    return null;
  }

  @override
  Future<void> actualizar(ConfiguracionDeRastreo config) async {
    _config = config;
    _detector?.config = config;
    if (_flujoPreciso == true) await _abrirFlujo(preciso: true, forzar: true);
  }

  @override
  Future<void> detener() async {
    _activa = false;
    _tic?.cancel();
    _tic = null;
    await _actividad?.cancel();
    _actividad = null;
    await _acel?.cancel();
    _acel = null;
    _movDesde = null;
    await _cerrarFlujo();
    _detector = null;
  }

  /// El movimiento cuenta si pasa de [ConfiguracionDeRastreo.despertarAceleracion]; un hueco de
  /// hasta 1,5 s no corta la racha (caminar tiene instantes de calma entre paso y paso).
  void _alAcelerometro(AccelerometerEvent e) {
    // Muchos teléfonos (el Honor LLY-LX3 entre ellos) no traen el sensor «sin gravedad»: se usa el
    // acelerómetro común y se le resta la gravedad con un filtro que la sigue lenta (alfa 0,9).
    _gx = 0.9 * _gx + 0.1 * e.x;
    _gy = 0.9 * _gy + 0.1 * e.y;
    _gz = 0.9 * _gz + 0.1 * e.z;
    final lx = e.x - _gx, ly = e.y - _gy, lz = e.z - _gz;
    final d = _detector;
    if (d == null || d.estado != EstadoDeMovimiento.quieto) {
      _movDesde = null;
      return;
    }
    final ahora = DateTime.now().millisecondsSinceEpoch;
    final mag = math.sqrt(lx * lx + ly * ly + lz * lz);
    if (mag >= _config.despertarAceleracion) {
      _ultimoMov = ahora;
      _movDesde ??= ahora;
    } else if (_movDesde != null && ahora - _ultimoMov > 1500) {
      _movDesde = null;
    }
    final desde = _movDesde;
    if (desde != null && ahora - desde >= _config.despertarSeg * 1000) {
      _movDesde = null;
      unawaited(_aplicar(d.actividad(TipoDeActividad.aPie, ahora)));
    }
  }

  Future<void> _cerrarFlujo() async {
    final f = _flujo;
    _flujo = null;
    _flujoPreciso = null;
    try {
      await f?.cancel();
    } catch (_) {}
  }

  Future<void> _abrirFlujo({required bool preciso, bool forzar = false}) async {
    if (!_activa) return;
    if (!forzar && _flujoPreciso == preciso && _flujo != null) return;
    await _cerrarFlujo();
    try {
      _flujo = Geolocator.getPositionStream(locationSettings: _ajustes(preciso)).listen(
        (p) => _llego(p, preciso),
        onError: (Object e) {
          _eventos.add(ProblemaDeCaptura('el GPS se cortó: $e'));
          _flujo = null;
          _flujoPreciso = null;
        },
        cancelOnError: true,
      );
      _flujoPreciso = preciso;
    } catch (e) {
      _eventos.add(ProblemaDeCaptura(
          'no se pudo abrir el GPS ${preciso ? 'preciso' : 'de bajo consumo'}: $e'));
    }
  }

  LocationSettings _ajustes(bool preciso) {
    final cada = Duration(seconds: _config.muestreoDelGpsSeg);
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: preciso ? LocationAccuracy.best : LocationAccuracy.low,
        distanceFilter: preciso ? 0 : 100,
        intervalDuration: preciso ? cada : const Duration(minutes: 1),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: textos.titulo,
          notificationText: textos.cuerpo,
          notificationChannelName: textos.canal,
          // 🔴 Sin wake lock: con el GPS preciso prendido el sistema despierta solo para
          // entregar; un wake lock mantendría el procesador despierto también en QUIETO.
          enableWakeLock: false,
          setOngoing: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: preciso ? LocationAccuracy.best : LocationAccuracy.reduced,
        distanceFilter: preciso ? 0 : 100,
        activityType: ActivityType.otherNavigation,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        // 🔴 En falso: si iOS pausa solo, en el fondo no vuelve a arrancar sin una
        // región — y entonces la persona sale y no se graba nada.
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return LocationSettings(accuracy: preciso ? LocationAccuracy.best : LocationAccuracy.low);
  }

  Future<void> _llego(Position p, bool preciso) async {
    final d = _detector;
    if (d == null) return;
    final l = Lectura(
      t: p.timestamp.millisecondsSinceEpoch,
      lat: p.latitude,
      lon: p.longitude,
      acc: p.accuracy,
      v: p.speed,
      // geolocator pone 0.0 cuando el sistema no da el dato (y 0 es el norte y el nivel
      // del mar): se mira la bandera `has*`. iOS además marca el rumbo inválido con < 0.
      h: (p.hasHeading && p.heading >= 0) ? p.heading : PuntoDeRastreo.rumboDesconocido,
      alt: p.hasAltitude ? p.altitude : PuntoDeRastreo.altitudDesconocida,
      mock: p.isMocked,
    );
    final dec = d.lectura(l, precisa: preciso);
    if (dec.grabar) {
      _eventos.add(PuntoCapturado(
        PuntoDeRastreo(
          t: l.t,
          lat: l.lat,
          lon: l.lon,
          acc: l.acc,
          v: dec.velocidad,
          h: l.h,
          alt: l.alt,
          mock: l.mock,
          bat: await _bateriaAhora(),
        ),
        d.tramo,
        hueco: dec.hueco,
      ));
    }
    await _aplicar(dec);
  }

  Future<void> _aplicar(Decision dec) async {
    if (dec.cambio) {
      _eventos.add(CambioDeEstado(dec.estado, dec.motivo, vaciar: dec.vaciar));
    } else if (dec.cambioDeFila) {
      _eventos.add(CambioDeEstado(dec.estado, 'cadencia: ${dec.fila.estado}'));
    }
    await _abrirFlujo(preciso: dec.gpsPreciso);
  }

  /// La batería se lee a lo sumo una vez por minuto: leerla en cada punto es un viaje al
  /// nativo cada cinco segundos para un número que cambia cada diez minutos.
  Future<int> _bateriaAhora() async {
    final ahora = DateTime.now();
    if (_bateriaLeida == null || ahora.difference(_bateriaLeida!) > const Duration(minutes: 1)) {
      try {
        _nivelDeBateria = await _bateria.batteryLevel;
      } catch (_) {
        _nivelDeBateria = -1;
      }
      _bateriaLeida = ahora;
    }
    return (_nivelDeBateria < 0 || _nivelDeBateria > 100)
        ? PuntoDeRastreo.bateriaDesconocida
        : _nivelDeBateria;
  }
}
