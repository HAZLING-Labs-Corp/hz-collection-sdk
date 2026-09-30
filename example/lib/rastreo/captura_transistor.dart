/// LA CAPTURA DE TRANSISTOR — `flutter_background_geolocation`, para medir D-04 contra la
/// propia del SDK.
///
/// Vive en la APP DE EJEMPLO y no en el SDK a propósito: ver la cabecera de
/// `lib/src/rastreo/captura.dart` en el paquete (inyectaría sus permisos a toda app).
///
/// ══ QUÉ HACE TRANSISTOR Y QUÉ HACEMOS NOSOTROS ══
///
/// **Transistor detecta y enciende**: su reconocimiento de actividad y su geocerca de reposo
/// deciden cuándo se mueve (`onMotionChange`) y prenden y apagan el GPS a los `quietoMin`
/// (`stopTimeout`). **Nosotros confirmamos y grabamos**: cada ubicación pasa por el MISMO
/// `DetectorDeMovimiento` de la captura propia —la confirmación por velocidad, el ritmo de
/// ciudad o rápida, los huecos—, así que lo que se compara entre las dos es la detección y
/// la supervivencia en el fondo, no dos criterios de grabación distintos.
///
/// Su base de datos y su HTTP quedan APAGADOS: la cola y la firma son del SDK.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:hz_collection_sdk/hz_collection_sdk.dart';

class CapturaTransistor implements CapturaDeRastreo {
  CapturaTransistor({required this.tituloDelAviso, required this.cuerpoDelAviso});

  final String tituloDelAviso;
  final String cuerpoDelAviso;

  @override
  String get nombre => 'transistor';

  final _eventos = StreamController<EventoDeCaptura>.broadcast();
  @override
  Stream<EventoDeCaptura> get eventos => _eventos.stream;

  DetectorDeMovimiento? _detector;
  Timer? _tic;
  bool _activa = false;
  bool _preparada = false;
  ConfiguracionDeRastreo _config = ConfiguracionDeRastreo.apagada;

  @override
  bool get activa => _activa;

  @override
  EstadoDeMovimiento get estado => _detector?.estado ?? EstadoDeMovimiento.quieto;

  @override
  FilaDeCadencia get cadencia => _detector?.fila ?? FilaDeCadencia.respaldo;

  bg.Config _aConfig(ConfiguracionDeRastreo c) => bg.Config(
        geolocation: bg.GeoConfig(
          desiredAccuracy: bg.DesiredAccuracy.high,
          // Android: con distancia 0 manda el intervalo. Al ritmo rápido; el de ciudad lo
          // aplica el detector según la fila de cadencia, igual que en la propia.
          distanceFilter: defaultTargetPlatform == TargetPlatform.iOS ? 10 : 0,
          locationUpdateInterval: c.muestreoDelGpsSeg * 1000,
          fastestLocationUpdateInterval: c.muestreoDelGpsSeg * 1000,
          stopTimeout: c.quietoMin,
          stationaryRadius: 150,
          disableElasticity: true,
          locationAuthorizationRequest: 'Always',
          pausesLocationUpdatesAutomatically: false,
          showsBackgroundLocationIndicator: true,
        ),
        activity: const bg.ActivityConfig(motionTriggerDelay: 0),
        app: bg.AppConfig(
          // Que sobreviva a que la barran de las recientes y al reinicio: es la mitad de lo
          // que Transistor vende y lo que D-04 tiene que medir.
          stopOnTerminate: false,
          startOnBoot: true,
          enableHeadless: false,
          notification: bg.Notification(title: tituloDelAviso, text: cuerpoDelAviso, sticky: true),
        ),
        persistence: const bg.PersistenceConfig(persistMode: bg.PersistMode.none),
        logger: const bg.LoggerConfig(debug: false, logLevel: bg.LogLevel.warning),
      );

  @override
  Future<String?> iniciar(ConfiguracionDeRastreo config) async {
    _config = config;
    _detector ??= DetectorDeMovimiento(config);
    try {
      if (!_preparada) {
        bg.BackgroundGeolocation.onLocation(_llego, (e) {
          _eventos.add(ProblemaDeCaptura('transistor: ${e.code} ${e.message}'));
        });
        bg.BackgroundGeolocation.onMotionChange(_cambioDeMovimiento);
        bg.BackgroundGeolocation.onProviderChange((e) {
          if (!e.enabled) _eventos.add(const ProblemaDeCaptura('el GPS del teléfono se apagó'));
        });
        await bg.BackgroundGeolocation.ready(_aConfig(config));
        _preparada = true;
      } else {
        await bg.BackgroundGeolocation.setConfig(_aConfig(config));
      }
      await bg.BackgroundGeolocation.start();
      _activa = true;
      // La tabla de cadencia se reevalúa cada pocos segundos también sin lecturas.
      _tic ??= Timer.periodic(const Duration(seconds: 5), (_) {
        final d = _detector;
        if (d == null) return;
        final dec = d.tic(DateTime.now().millisecondsSinceEpoch);
        if (dec.cambio) {
          _eventos.add(CambioDeEstado(dec.estado, dec.motivo, vaciar: dec.vaciar));
        } else if (dec.cambioDeFila) {
          _eventos.add(CambioDeEstado(dec.estado, 'cadencia: ${dec.fila.estado}'));
        }
      });
      _eventos.add(const CambioDeEstado(EstadoDeMovimiento.quieto, 'transistor arrancó'));
      return null;
    } catch (e) {
      return 'transistor no arrancó: $e';
    }
  }

  @override
  Future<void> actualizar(ConfiguracionDeRastreo config) async {
    _config = config;
    _detector?.config = config;
    if (_preparada) await bg.BackgroundGeolocation.setConfig(_aConfig(config));
  }

  @override
  Future<void> detener() async {
    _activa = false;
    _tic?.cancel();
    _tic = null;
    try {
      await bg.BackgroundGeolocation.stop();
    } catch (_) {}
  }

  void _cambioDeMovimiento(bg.Location l) {
    final d = _detector;
    if (d == null) return;
    final t = DateTime.now().millisecondsSinceEpoch;
    if (l.isMoving) {
      final dec = d.actividad(TipoDeActividad.vehiculo, t);
      if (dec.cambio) {
        _eventos.add(CambioDeEstado(dec.estado, 'transistor: se mueve'));
      }
    } else {
      // Transistor ya apagó el GPS. Se reinicia el detector conservando el número de tramo.
      final tramo = d.tramo;
      _detector = DetectorDeMovimiento(_config)..tramo = tramo;
      _eventos.add(const CambioDeEstado(EstadoDeMovimiento.quieto, 'transistor: quieto',
          vaciar: true));
    }
  }

  void _llego(bg.Location l) {
    final d = _detector;
    if (d == null || l.sample) return;
    final ts = l.timestamp;
    final t = ts is int ? ts : DateTime.parse('$ts').millisecondsSinceEpoch;
    final lectura = Lectura(
      t: t,
      lat: l.coords.latitude,
      lon: l.coords.longitude,
      acc: l.coords.accuracy,
      v: l.coords.speed,
      h: l.coords.heading,
      alt: l.coords.altitude,
      mock: l.mock,
    );
    final antes = d.estado;
    final dec = d.lectura(lectura, precisa: true);
    if (dec.grabar) {
      _eventos.add(PuntoCapturado(
        PuntoDeRastreo(
          t: t,
          lat: lectura.lat,
          lon: lectura.lon,
          acc: lectura.acc,
          v: dec.velocidad,
          h: lectura.h,
          alt: lectura.alt,
          mock: lectura.mock,
          bat: (l.battery.level * 100).round(),
        ),
        d.tramo,
        hueco: dec.hueco,
      ));
    }
    if (dec.cambio && d.estado != antes) {
      _eventos.add(CambioDeEstado(dec.estado, dec.motivo, vaciar: dec.vaciar));
    } else if (dec.cambioDeFila) {
      _eventos.add(CambioDeEstado(dec.estado, 'cadencia: ${dec.fila.estado}'));
    }
  }
}
