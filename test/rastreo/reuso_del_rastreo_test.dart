import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hz_collection_sdk/src/rastreo/cadencia.dart';
import 'package:hz_collection_sdk/src/rastreo/captura.dart';
import 'package:hz_collection_sdk/src/rastreo/cola_de_rastreo.dart';
import 'package:hz_collection_sdk/src/rastreo/configuracion_de_rastreo.dart';
import 'package:hz_collection_sdk/src/rastreo/detector_de_movimiento.dart';
import 'package:hz_collection_sdk/src/rastreo/rastreo.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'cadencia_test.dart' show tablaDelContrato;

/// Una captura que anota lo que le hacen y lo que emite.
class _Captura implements CapturaDeRastreo {
  _Captura(this.nombre);
  @override
  final String nombre;
  final _eventos = StreamController<EventoDeCaptura>.broadcast();
  final emitidos = <EventoDeCaptura>[];
  var iniciada = 0;
  var detenida = 0;
  @override
  Stream<EventoDeCaptura> get eventos => _eventos.stream;
  @override
  EstadoDeMovimiento estado = EstadoDeMovimiento.quieto;
  @override
  FilaDeCadencia get cadencia => FilaDeCadencia.respaldo;
  @override
  bool activa = false;
  void emitir(EventoDeCaptura e) {
    emitidos.add(e);
    _eventos.add(e);
  }

  @override
  Future<String?> iniciar(ConfiguracionDeRastreo config) async {
    iniciada++;
    activa = true;
    emitir(const CambioDeEstado(EstadoDeMovimiento.quieto, 'arrancó'));
    return null;
  }

  @override
  Future<void> actualizar(ConfiguracionDeRastreo config) async {}
  @override
  Future<void> detener() async {
    detenida++;
    activa = false;
  }
}

void main() {
  sqfliteFfiInit();
  final cliente = MockClient((_) async => http.Response('{}', 202));
  late ColaDeRastreo cola;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'a', packageName: 'p', version: '1', buildNumber: '1', buildSignature: '');
    cola = await ColaDeRastreo.abrir(
        ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi, topePuntos: 100, topeBytes: 1 << 20);
  });
  tearDown(() async {
    Rastreo.vivoParaPruebas = null;
    await cola.cerrar();
  });

  Future<Rastreo> abrir(CapturaDeRastreo c, {String llave = 'pk_prueba'}) =>
      Rastreo.abrir(llave: llave, url: 'http://api', captura: c, cola: cola, cliente: cliente);

  group('volver a abrir el rastreo en pleno viaje', () {
    test('con lo mismo: la MISMA instancia, sigue rodando y no hay ningún «arrancó»', () async {
      final primera = _Captura('propia');
      final a = await abrir(primera);
      primera
        ..activa = true
        ..estado = EstadoDeMovimiento.rodando;
      Rastreo.vivoParaPruebas = a; // lo que deja `iniciar`
      a.declararMedio('dosRuedas');

      final segunda = _Captura('propia'); // la pantalla nueva arma otra captura
      final b = await abrir(segunda);

      expect(identical(a, b), isTrue);
      expect(b.captura, same(primera));
      expect(b.captura.estado, EstadoDeMovimiento.rodando);
      expect(primera.detenida, 0);
      expect(segunda.iniciada, 0);
      expect(primera.emitidos.whereType<CambioDeEstado>().where((e) => e.motivo == 'arrancó'), isEmpty);
      expect(b.medioDeclarado, 'dosRuedas');
    });

    test('con otra captura (o otra llave) sí se arma otra', () async {
      final a = await abrir(_Captura('propia'));
      Rastreo.vivoParaPruebas = a;
      expect(identical(await abrir(_Captura('transistor')), a), isFalse);
      expect(identical(await abrir(_Captura('propia'), llave: 'pk_otra'), a), isFalse);
    });

    test('sin nada corriendo, cada abrir es una instancia nueva (como antes)', () async {
      final a = await abrir(_Captura('propia'));
      expect(identical(await abrir(_Captura('propia')), a), isFalse);
    });
  });

  group('el relevo entre capturas', () {
    final c = ConfiguracionDeRastreo.fromJson(
        {'activo': true, 'quietoMin': 5, 'arranqueKmh': 10, 'cadencia': tablaDelContrato});
    Lectura l(int seg, double m, {double v = -1}) =>
        Lectura(t: 1000000 + seg * 1000, lat: 10.0 + m / 111195, lon: -66.9, acc: 5, v: v);

    test('el detector nuevo sigue en RODANDO: graba desde la primera lectura, no reconfirma', () {
      final d = DetectorDeMovimiento(c);
      final arranque = d.continuarRodando(1000000);
      expect(arranque.estado, EstadoDeMovimiento.rodando);
      expect(arranque.cambio, isTrue);
      expect(arranque.gpsPreciso, isTrue);
      expect(d.tramo, 1);
      final primera = d.lectura(l(2, 30, v: 12), precisa: true);
      expect(primera.estado, EstadoDeMovimiento.rodando);
      expect(primera.grabar, isTrue);
    });

    test('y si de verdad estaba parado, se concluye quieto como siempre', () {
      final d = DetectorDeMovimiento(c)..continuarRodando(1000000);
      d.lectura(l(0, 0, v: 0), precisa: true);
      final fin = d.lectura(l(6 * 60, 1, v: 0), precisa: true);
      expect(fin.estado, EstadoDeMovimiento.quieto);
    });
  });
}
