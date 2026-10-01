import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hz_collection_sdk/hz_collection_sdk.dart' as publico;
import 'package:hz_collection_sdk/src/rastreo/cadencia.dart';
import 'package:hz_collection_sdk/src/rastreo/captura.dart';
import 'package:hz_collection_sdk/src/rastreo/cola_de_rastreo.dart';
import 'package:hz_collection_sdk/src/rastreo/configuracion_de_rastreo.dart';
import 'package:hz_collection_sdk/src/rastreo/detector_de_movimiento.dart';
import 'package:hz_collection_sdk/src/rastreo/golpe/detector_de_golpe.dart';
import 'package:hz_collection_sdk/src/rastreo/medio_del_viaje.dart';
import 'package:hz_collection_sdk/src/rastreo/rastreo.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Captura implements CapturaDeRastreo {
  @override
  String get nombre => 'prueba';
  @override
  Stream<EventoDeCaptura> get eventos => const Stream.empty();
  @override
  EstadoDeMovimiento estado = EstadoDeMovimiento.quieto;
  @override
  FilaDeCadencia get cadencia => FilaDeCadencia.respaldo;
  @override
  bool activa = false;
  @override
  Future<String?> iniciar(ConfiguracionDeRastreo config) async => null;
  @override
  Future<void> actualizar(ConfiguracionDeRastreo config) async {}
  @override
  Future<void> detener() async {}
}

const _quieto = EstadoDeMovimiento.quieto;
const _confirmando = EstadoDeMovimiento.confirmando;
const _rodando = EstadoDeMovimiento.rodando;
const _t0 = 1727700000000;

void main() {
  sqfliteFfiInit();

  group('simularGolpe con confianza mínima', () {
    const u = UmbralesDeGolpe(gPico: 4, quietudSeg: 60);

    test('sin pedir nada da lo de siempre (≈0,63)', () {
      final g = golpeSintetico(umbrales: u, desde: _t0)!;
      expect(g.confianza, lessThan(0.7));
      expect(g.confianza, greaterThan(0.55));
    });

    test('pidiendo 0,8 sale uno que la supera, y el pico es más fuerte', () {
      final g = golpeSintetico(umbrales: u, desde: _t0, confianzaMinima: 0.8)!;
      expect(g.confianza, greaterThanOrEqualTo(0.8));
      expect(g.pico, greaterThanOrEqualTo(8));
    });

    test('pidiendo poco no se fuerza de más: el primer intento alcanza', () {
      final g = golpeSintetico(umbrales: u, desde: _t0, confianzaMinima: 0.5)!;
      expect(g.pico, closeTo(6, 0.01));
    });

    test('lo imposible devuelve el más fuerte, no null', () {
      final g = golpeSintetico(umbrales: u, desde: _t0, confianzaMinima: 1.01)!;
      expect(g.confianza, greaterThan(0.9));
      expect(g.conGps, isTrue);
    });
  });

  group('estadoDeMedicionDe', () {
    publico.EstadoDeMedicion e({
      publico.EstadoDelConsentimiento c = publico.EstadoDelConsentimiento.concedido,
      bool? permiso = true,
      bool? gps = true,
      bool activa = true,
      bool apagado = false,
      bool corriendo = true,
      bool captura = true,
    }) =>
        estadoDeMedicionDe(
            consentimiento: c,
            permisoConcedido: permiso,
            ubicacionPrendida: gps,
            configuracionActiva: activa,
            apagadoPorElServidor: apagado,
            corriendo: corriendo,
            capturaActiva: captura);

    test('cada caso, y la precedencia', () {
      expect(e(), publico.EstadoDeMedicion.midiendo);
      expect(e(c: publico.EstadoDelConsentimiento.negado, permiso: false), publico.EstadoDeMedicion.sinConsentimiento);
      expect(e(c: publico.EstadoDelConsentimiento.nuncaPreguntado), publico.EstadoDeMedicion.sinConsentimiento);
      expect(e(permiso: false, gps: false), publico.EstadoDeMedicion.sinPermiso);
      expect(e(gps: false, apagado: true), publico.EstadoDeMedicion.apagadoPorLaPersona);
      expect(e(apagado: true), publico.EstadoDeMedicion.apagadoPorElServidor);
      expect(e(activa: false, captura: false), publico.EstadoDeMedicion.apagadoPorElServidor);
      expect(e(corriendo: false, activa: false), publico.EstadoDeMedicion.detenido);
      expect(e(captura: false), publico.EstadoDeMedicion.detenido);
      expect(e(permiso: null, gps: null), publico.EstadoDeMedicion.midiendo, reason: 'sin leer no se afirma que falte');
    });
  });

  group('el medio por omisión', () {
    test('sin declarar manda el de por omisión; el declarado le gana', () {
      final m = MedioDelViaje()..porOmision = 'carro';
      expect(m.vigente, 'carro');
      expect(m.paraLote(_t0), 'carro');
      m.declarar('bici', _quieto);
      expect(m.vigente, 'bici');
      expect(m.paraLote(_t0), 'bici');
    });

    test('al terminar el viaje declarado vuelve al de por omisión, no a null', () {
      final m = MedioDelViaje()..porOmision = 'dosRuedas';
      m.declarar('bus', _quieto);
      m.cambio(_confirmando, _t0);
      m.cambio(_rodando, _t0 + 10000);
      expect(m.cambio(_quieto, _t0 + 400000), isTrue);
      expect(m.declarado, isNull);
      expect(m.vigente, 'dosRuedas');
      expect(m.paraLote(_t0 + 10000), 'bus', reason: 'el último lote del viaje lleva su medio');
      expect(m.paraLote(_t0 + 500000), 'dosRuedas', reason: 'el viaje siguiente');
    });
  });

  group('Rastreo: medio por omisión, consentimiento, estado y última posición', () {
    late ColaDeRastreo cola;
    setUp(() async {
      PackageInfo.setMockInitialValues(
          appName: 'a', packageName: 'p', version: '1', buildNumber: '1', buildSignature: '');
      cola = await ColaDeRastreo.abrir(
          ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi, topePuntos: 100, topeBytes: 1 << 20);
    });
    tearDown(() async {
      Rastreo.vivoParaPruebas = null;
      await cola.cerrar();
    });
    Future<Rastreo> abrir() => Rastreo.abrir(
        llave: 'pk_prueba', url: 'http://api', captura: _Captura(), cola: cola,
        cliente: MockClient((_) async => http.Response('{}', 202)));

    test('fijarMedioPorOmision persiste en otra instancia, y valida el vocabulario', () async {
      SharedPreferences.setMockInitialValues({});
      final a = await abrir();
      expect(a.medioPorOmision, isNull);
      await a.fijarMedioPorOmision('dosRuedas');
      expect(a.medioVigente, 'dosRuedas');
      expect(a.medioDeclarado, isNull, reason: 'no es un viaje declarado');
      final b = await abrir();
      expect(b.medioPorOmision, 'dosRuedas');
      b.declararMedio('pie');
      expect(b.medioVigente, 'pie');
      b.declararMedio(null);
      expect(b.medioVigente, 'dosRuedas');
      expect(() => b.fijarMedioPorOmision('moto'), throwsArgumentError);
      await b.fijarMedioPorOmision(null);
      expect((await abrir()).medioPorOmision, isNull);
    });

    test('el consentimiento distingue nunca, sí y no; consentimientoAnotado sigue igual', () async {
      SharedPreferences.setMockInitialValues({});
      final a = await abrir();
      expect(await a.estadoDelConsentimiento(), publico.EstadoDelConsentimiento.nuncaPreguntado);
      expect(await a.consentimientoAnotado(), isFalse);
      SharedPreferences.setMockInitialValues({'hz_rastreo_consentimiento_anotado': false});
      expect(await a.estadoDelConsentimiento(), publico.EstadoDelConsentimiento.negado);
      expect(await a.consentimientoAnotado(), isFalse);
      SharedPreferences.setMockInitialValues({'hz_rastreo_consentimiento_anotado': true});
      expect(await a.estadoDelConsentimiento(), publico.EstadoDelConsentimiento.concedido);
      expect(await a.consentimientoAnotado(), isTrue);
    });

    test('sin iniciar: estado sinConsentimiento o detenido, y sin última posición', () async {
      SharedPreferences.setMockInitialValues({});
      final a = await abrir();
      expect(a.estadoDeMedicion, publico.EstadoDeMedicion.sinConsentimiento);
      expect(a.ultimaPosicion, isNull);
      SharedPreferences.setMockInitialValues({'hz_rastreo_consentimiento_anotado': true});
      final b = await abrir();
      expect(b.estadoDeMedicion, publico.EstadoDeMedicion.detenido);
    });

    test('el stream avisa los cambios de estado, sin repetir', () async {
      SharedPreferences.setMockInitialValues({'hz_rastreo_consentimiento_anotado': true});
      final a = await abrir();
      final vistos = <publico.EstadoDeMedicion>[];
      final sub = a.estadosDeMedicion.listen(vistos.add);
      a.declararMedio('pie'); // un cambio que no mueve el estado
      a.declararMedio('bici');
      await Future<void>.delayed(Duration.zero);
      expect(vistos, [publico.EstadoDeMedicion.detenido]);
      await sub.cancel();
    });
  });
}
