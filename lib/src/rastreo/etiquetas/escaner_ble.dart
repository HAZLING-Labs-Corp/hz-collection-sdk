/// EL ESCÁNER BLE — detrás de una interfaz, para probar sin radio.
///
/// La implementación usa `flutter_reactive_ble` (Philips Hue / Signify, BSD-3, sobre
/// RxAndroidBle en Android y CoreBluetooth en iOS). Se eligió sobre `flutter_blue_plus` porque
/// éste dejó la licencia BSD por una propia que pide licencia comercial a empresas; sobre los
/// plugins de «beacons» porque son de un autor, con pocas descargas, y algunos arrastran un
/// servicio en primer plano propio. El SDK sólo ESCANEA: nunca conecta (no hace falta
/// `BLUETOOTH_CONNECT`).
///
/// ⚠️ iOS no entrega los anuncios iBeacon a CoreBluetooth (los filtra el sistema): en iPhone sólo
/// se oyen Eddystone-UID y AltBeacon. En Android se oyen los tres.
library;

import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'etiquetas_ble.dart';

abstract class EscanerBle {
  /// Los anuncios que se oyen mientras dure la suscripción. Si el Bluetooth está apagado o
  /// falta el permiso, el flujo termina con error: quien escucha lo anota y sigue.
  /// [rapido]: escaneo de baja latencia (gasta más) — sólo con una pantalla abierta mirando.
  Stream<AnuncioBle> escuchar({bool rapido = false});
}

/// Todos los [EscanerReactivo] del proceso comparten UN escaneo de verdad ([_Radio]): con
/// `flutter_reactive_ble` cada `scanForDevices` nuevo corta el anterior, y el vigía (cada 30 s,
/// 8 s de escucha) le apagaba el escaneo al medidor de «Mi etiqueta»: a los 10 s decía
/// «desincronizada» con la etiqueta al lado (Juan, 2026-10-01).
class EscanerReactivo implements EscanerBle {
  EscanerReactivo([FlutterReactiveBle? ble]) : _ble = ble;
  final FlutterReactiveBle? _ble;

  @override
  Stream<AnuncioBle> escuchar({bool rapido = false}) => _Radio.de(_ble).escuchar(rapido);
}

class _Oyente {
  _Oyente(this.rapido);
  final bool rapido;
  late final StreamController<AnuncioBle> salida;
}

/// El único escaneo: rápido si alguno lo pide rápido; se rehace sólo al cambiar de modo y se
/// apaga cuando no queda nadie escuchando.
class _Radio {
  _Radio(this._ble);
  static _Radio? _unico;
  static _Radio de(FlutterReactiveBle? ble) => _unico ??= _Radio(ble ?? FlutterReactiveBle());

  final FlutterReactiveBle _ble;
  final _oyentes = <_Oyente>[];
  StreamSubscription<AnuncioBle>? _escaneo;
  bool? _modo;

  static final _feaa = Uuid.parse('feaa');

  Stream<AnuncioBle> escuchar(bool rapido) {
    final o = _Oyente(rapido);
    o.salida = StreamController<AnuncioBle>(
      onListen: () {
        _oyentes.add(o);
        _ajustar();
      },
      onCancel: () {
        _oyentes.remove(o);
        _ajustar();
      },
    );
    return o.salida.stream;
  }

  void _ajustar() {
    if (_oyentes.isEmpty) {
      unawaited(_escaneo?.cancel());
      _escaneo = null;
      _modo = null;
      return;
    }
    final rapido = _oyentes.any((o) => o.rapido);
    if (_escaneo != null && _modo == rapido) return;
    unawaited(_escaneo?.cancel());
    _modo = rapido;
    _escaneo = _ble
        // sin filtro de servicio: iBeacon y AltBeacon no anuncian ninguno; lowPower = menos batería (rodando)
        .scanForDevices(withServices: const [], scanMode: rapido ? ScanMode.lowLatency : ScanMode.lowPower, requireLocationServicesEnabled: false)
        .map((d) => AnuncioBle(
              rssi: d.rssi,
              fabricante: d.manufacturerData.isEmpty ? null : d.manufacturerData,
              servicios: {
                for (final e in d.serviceData.entries)
                  if (e.key == _feaa) 'feaa': e.value,
              },
            ))
        .listen(
          (a) {
            for (final o in List.of(_oyentes)) {
              o.salida.add(a);
            }
          },
          // Bluetooth apagado o sin permiso: el flujo de cada uno termina con el error, como antes
          onError: (Object e, StackTrace st) => _terminar((o) => o.salida.addError(e, st)),
          onDone: () => _terminar((_) {}),
        );
  }

  void _terminar(void Function(_Oyente) antes) {
    final todos = List.of(_oyentes);
    _oyentes.clear();
    _escaneo = null;
    _modo = null;
    for (final o in todos) {
      antes(o);
      unawaited(o.salida.close());
    }
  }
}
