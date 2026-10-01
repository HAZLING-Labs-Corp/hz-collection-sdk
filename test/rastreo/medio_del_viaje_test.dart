import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hz_collection_sdk/src/rastreo/api_de_rastreo.dart';
import 'package:hz_collection_sdk/src/rastreo/cola_de_rastreo.dart';
import 'package:hz_collection_sdk/src/rastreo/configuracion_de_rastreo.dart';
import 'package:hz_collection_sdk/src/rastreo/detector_de_movimiento.dart';
import 'package:hz_collection_sdk/src/rastreo/emisor_de_lotes.dart';
import 'package:hz_collection_sdk/src/rastreo/lote.dart';
import 'package:hz_collection_sdk/src/rastreo/medio_del_viaje.dart';
import 'package:hz_collection_sdk/src/rastreo/punto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Firmador implements FirmadorDeLotes {
  @override
  String get claveId => 'cd' * 32;
  @override
  Future<String> firmar(List<int> bytes) async => base64.encode(bytes.take(8).toList());
}

const _quieto = EstadoDeMovimiento.quieto;
const _confirmando = EstadoDeMovimiento.confirmando;
const _rodando = EstadoDeMovimiento.rodando;
const _arranque = 15 / 3.6;
const _t0 = 1727700000000;

PuntoDeRastreo _p(int t, {double v = 8}) => PuntoDeRastreo(
    t: t, lat: 10.49, lon: -66.87, acc: 5, v: v, h: 90, alt: 900, mock: false, bat: 80);

void main() {
  /// El viaje anterior en carro: declarado, rodó y el detector quedó en rodando (la simulación
  /// terminó y el GPS dejó de entregar; la quietud la concluye después el reloj del detector).
  MedioDelViaje viajeAnteriorQueQuedoRodando() {
    final m = MedioDelViaje()..declarar('carro', _quieto);
    m.cambio(_confirmando, _t0);
    m.cambio(_rodando, _t0 + 10000);
    m.punto(_rodando, 12, _arranque);
    return m;
  }

  group('el medio declarado', () {
    test('el caso medido: declarar con el rodando heredado, quietud del arranque, rodar', () {
      final m = viajeAnteriorQueQuedoRodando();
      m.declarar('dosRuedas', _rodando); // la captura todavía dice rodando
      // segundo 6: el reloj del detector concluye la quietud del viaje VIEJO
      expect(m.cambio(_quieto, _t0 + 60000), isFalse);
      expect(m.declarado, 'dosRuedas');
      // parado al salir: un punto quieto, una confirmación que no prospera
      m.punto(_quieto, 0, _arranque);
      expect(m.cambio(_confirmando, _t0 + 70000), isFalse);
      expect(m.cambio(_quieto, _t0 + 80000), isFalse);
      expect(m.declarado, 'dosRuedas');
      // ahora sí rueda
      m.cambio(_confirmando, _t0 + 90000);
      m.cambio(_rodando, _t0 + 100000);
      m.punto(_rodando, 9, _arranque);
      expect(m.declarado, 'dosRuedas', reason: 'la presencia sale con el medio');
      expect(m.paraLote(_t0 + 90000), 'dosRuedas', reason: 'y el lote también');
      // quieto después de rodar: fin del viaje, se olvida
      expect(m.cambio(_quieto, _t0 + 400000), isTrue);
      expect(m.declarado, isNull);
    });

    test('el rodando heredado: un cambio de fila o un punto parado no cuentan como rodar', () {
      final m = viajeAnteriorQueQuedoRodando();
      m.declarar('dosRuedas', _rodando);
      m.cambio(_rodando, _t0 + 20000); // «cadencia: …», mismo estado
      m.punto(_rodando, 0, _arranque);
      expect(m.cambio(_quieto, _t0 + 60000), isFalse);
      expect(m.declarado, 'dosRuedas');
    });

    test('declarado en pleno viaje, a velocidad: al quedar quieto se olvida', () {
      final m = MedioDelViaje()..declarar('bus', _rodando);
      m.punto(_rodando, 10, _arranque);
      expect(m.cambio(_quieto, _t0), isTrue);
      expect(m.declarado, isNull);
    });

    test('el viaje anterior terminó bien y se declara quieto: la quietud inicial no lo borra', () {
      final m = MedioDelViaje();
      m.cambio(_rodando, _t0);
      m.cambio(_quieto, _t0 + 10000);
      m.declarar('pie', _quieto);
      expect(m.cambio(_quieto, _t0 + 20000), isFalse);
      expect(m.cambio(_confirmando, _t0 + 30000), isFalse);
      expect(m.cambio(_quieto, _t0 + 40000), isFalse);
      expect(m.declarado, 'pie');
    });

    test('null vuelve al del perfil', () {
      final m = MedioDelViaje()..declarar('carro', _quieto);
      m.declarar(null, _quieto);
      expect(m.declarado, isNull);
      expect(m.paraLote(_t0), isNull);
    });
  });

  group('el medio en el lote', () {
    sqfliteFfiInit();
    late ColaDeRastreo cola;
    late List<http.Request> pedidos;
    late MedioDelViaje m;
    late EmisorDeLotes e;

    setUp(() async {
      cola = await ColaDeRastreo.abrir(
          ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi, topePuntos: 20000, topeBytes: 4 << 20);
      await cola.escribir('claveRegistrada', 'si');
      pedidos = [];
      m = viajeAnteriorQueQuedoRodando();
      e = EmisorDeLotes(
        cola: cola,
        api: ApiDeRastreo(
            llave: 'pk_prueba',
            url: 'http://ingesta/api/v1',
            cliente: MockClient((r) async {
              pedidos.add(r);
              return http.Response('{}', 202);
            })),
        firmador: _Firmador(),
        instalacionId: 'inst-1',
        reloj: (g) async => RelojDelLote(mono: 5000, arranques: 2, gnss: g),
        configuracion: () => const ConfiguracionDeRastreo(activo: true, lotePuntos: 40),
        loteSeg: () => 300,
        registrarClave: () async => true,
        ahora: () => DateTime.fromMillisecondsSinceEpoch(_t0 + 3600000),
        azar: math.Random(1),
        medio: m.paraLote,
      );
    });
    tearDown(() => cola.cerrar());

    Future<Object?> medioDelUltimoLote() async {
      expect((await e.intentar(forzar: true)).que, 'enviado');
      return (jsonDecode(pedidos.last.body) as Map)['medio'];
    }

    test('el lote del viaje declarado lleva el medio, también el que se arma después de la quietud',
        () async {
      m.declarar('dosRuedas', _rodando);
      m.cambio(_quieto, _t0 + 60000); // la quietud heredada
      m.cambio(_confirmando, _t0 + 90000);
      m.cambio(_rodando, _t0 + 100000);
      await cola.agregar(_p(_t0 + 100000), 1);
      m.punto(_rodando, 8, _arranque);
      expect(await medioDelUltimoLote(), 'dosRuedas');

      await cola.agregar(_p(_t0 + 110000), 1);
      expect(m.cambio(_quieto, _t0 + 400000), isTrue); // fin del viaje: el emisor estaba ocupado
      expect(await medioDelUltimoLote(), 'dosRuedas', reason: 'trae puntos del viaje');

      await cola.agregar(_p(_t0 + 500000), 2); // otro viaje, sin declarar
      expect(await medioDelUltimoLote(), isNull);
    });
  });
}
