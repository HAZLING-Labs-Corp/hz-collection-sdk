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
  Stream<AnuncioBle> escuchar();
}

class EscanerReactivo implements EscanerBle {
  EscanerReactivo([FlutterReactiveBle? ble]) : _ble = ble;
  FlutterReactiveBle? _ble;

  static final _feaa = Uuid.parse('feaa');

  @override
  Stream<AnuncioBle> escuchar() {
    final ble = _ble ??= FlutterReactiveBle();
    return ble
        // sin filtro de servicio: iBeacon y AltBeacon no anuncian ninguno; lowPower = menos batería
        .scanForDevices(withServices: const [], scanMode: ScanMode.lowPower, requireLocationServicesEnabled: false)
        .map((d) => AnuncioBle(
              rssi: d.rssi,
              fabricante: d.manufacturerData.isEmpty ? null : d.manufacturerData,
              servicios: {
                for (final e in d.serviceData.entries)
                  if (e.key == _feaa) 'feaa': e.value,
              },
            ));
  }
}
