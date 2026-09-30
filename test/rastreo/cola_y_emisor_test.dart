import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hz_collection_sdk/src/rastreo/api_de_rastreo.dart';
import 'package:hz_collection_sdk/src/rastreo/canonico.dart';
import 'package:hz_collection_sdk/src/rastreo/cola_de_rastreo.dart';
import 'package:hz_collection_sdk/src/rastreo/configuracion_de_rastreo.dart';
import 'package:hz_collection_sdk/src/rastreo/emisor_de_lotes.dart';
import 'package:hz_collection_sdk/src/rastreo/lote.dart';
import 'package:hz_collection_sdk/src/rastreo/punto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Firma de mentira: el SHA-256 de los bytes en base64. La firma ES256 de verdad la prueba
/// el doble de la ingesta contra el emulador (ver RESUMEN-A.md); acá importa QUÉ se firma.
class _Firmador implements FirmadorDeLotes {
  @override
  String get claveId => 'cd' * 32;
  final firmados = <String>[];
  @override
  Future<String> firmar(List<int> bytes) async {
    firmados.add(utf8.decode(bytes));
    return base64.encode(utf8.encode(sha256Hex(utf8.decode(bytes))));
  }
}

PuntoDeRastreo _p(int i, {int base = 1727700000000}) => PuntoDeRastreo(
    t: base + i * 10000, lat: 10.49 + i * 0.0001, lon: -66.87, acc: 5, v: 8, h: 90,
    alt: 900, mock: false, bat: 80);

void main() {
  sqfliteFfiInit();
  final fabrica = databaseFactoryFfi;

  Future<ColaDeRastreo> abrir({int topePuntos = 20000, int topeBytes = 4 << 20}) =>
      ColaDeRastreo.abrir(
          ruta: inMemoryDatabasePath, fabrica: fabrica, topePuntos: topePuntos, topeBytes: topeBytes);

  group('la cola', () {
    test('guarda, ata a un lote y no vuelve a entregar lo atado', () async {
      final c = await abrir();
      for (var i = 0; i < 5; i++) {
        await c.agregar(_p(i), 1);
      }
      expect(await c.contarPendientes(), 5);
      final p = await c.pendientes(3);
      final l = await armarLote(
          instalacionId: 'i', loteId: 'l1', hashAnterior: '0',
          reloj: const RelojDelLote(mono: 1, arranques: 1), puntos: [for (final x in p) x.punto],
          firmador: _Firmador());
      await c.guardarLote(l, [for (final x in p) x.id], 1);
      expect(await c.contarPendientes(), 2);
      expect((await c.loteEnVuelo())!.loteId, 'l1');
      await c.cerrar();
    });

    test('el techo: primero lo enviado, después ralea lo que espera, nunca el lote en vuelo',
        () async {
      final c = await abrir(topePuntos: 100);
      // 30 enviados y aceptados.
      for (var i = 0; i < 30; i++) {
        await c.agregar(_p(i), 1);
      }
      final env = await c.pendientes(30);
      final l = await armarLote(
          instalacionId: 'i', loteId: 'viejo', hashAnterior: '0',
          reloj: const RelojDelLote(mono: 1, arranques: 1),
          puntos: [for (final x in env) x.punto], firmador: _Firmador());
      await c.guardarLote(l, [for (final x in env) x.id], 1);
      await c.marcarAceptado('viejo', l.hash);
      // 130 esperando: 160 filas > 100.
      for (var i = 30; i < 160; i++) {
        await c.agregar(_p(i), 2);
      }
      await c.respetarTecho();
      final t = await c.tamano();
      expect(t.filas, lessThanOrEqualTo(100));
      // Se perdieron puntos que esperaban, pero raleados: el primero y el último siguen.
      final quedan = await c.pendientes(1000);
      expect(quedan.first.punto.t, _p(30).t);
      expect(quedan.last.punto.t, _p(159).t);
      expect(await c.descartados(), greaterThan(0));
      expect(await c.ultimoHashAceptado(), l.hash);
      await c.cerrar();
    });
  });

  group('el emisor', () {
    late ColaDeRastreo cola;
    late List<http.Request> pedidos;
    late List<http.Response Function(http.Request)> respuestas;
    late DateTime ahora;
    late EmisorDeLotes e;
    var config = const ConfiguracionDeRastreo(activo: true, lotePuntos: 40);

    setUp(() async {
      cola = await abrir();
      await cola.escribir('claveRegistrada', 'si');
      pedidos = [];
      respuestas = [];
      ahora = DateTime.fromMillisecondsSinceEpoch(1727700000000 + 3600000);
      config = const ConfiguracionDeRastreo(activo: true, lotePuntos: 40);
      final cliente = MockClient((r) async {
        pedidos.add(r);
        final f = respuestas.isEmpty ? (_) => http.Response('{}', 202) : respuestas.removeAt(0);
        return f(r);
      });
      e = EmisorDeLotes(
        cola: cola,
        api: ApiDeRastreo(llave: 'pk_prueba', url: 'http://ingesta/api/v1', cliente: cliente),
        firmador: _Firmador(),
        instalacionId: 'inst-1',
        reloj: (g) async => RelojDelLote(mono: 5000, arranques: 2, gnss: g),
        configuracion: () => config,
        loteSeg: () => 300,
        registrarClave: () async => true,
        ahora: () => ahora,
        azar: math.Random(1),
      );
    });
    tearDown(() => cola.cerrar());

    test('con menos de 40 puntos y menos de 5 minutos no manda nada', () async {
      ahora = DateTime.fromMillisecondsSinceEpoch(1727700000000 + 100000);
      for (var i = 0; i < 10; i++) {
        await cola.agregar(_p(i), 1);
      }
      expect((await e.intentar()).que, 'nadaQueMandar');
      expect(pedidos, isEmpty);
    });

    test('40 puntos → un lote con la forma de §4.1, campo por campo', () async {
      for (var i = 0; i < 40; i++) {
        await cola.agregar(_p(i), 1);
      }
      final r = await e.intentar();
      expect(r.que, 'enviado');
      expect(pedidos, hasLength(1));
      final req = pedidos.single;
      expect(req.url.toString(), 'http://ingesta/api/v1/rastreo/lotes');
      expect(req.headers['authorization'], 'Bearer pk_prueba');
      final j = jsonDecode(req.body) as Map<String, dynamic>;
      expect(j.keys.toSet(), {
        'instalacionId', 'loteId', 'claveId', 'alg', 'hashAnterior', 'hash', 'firma', 'reloj', 'puntos'
      });
      expect(j['alg'], 'ES256');
      expect(j['hashAnterior'], '0');
      expect(j['reloj'], {'mono': 5000, 'arranques': 2, 'gnss': _p(39).t});
      expect((j['puntos'] as List), hasLength(40));
      expect((j['puntos'] as List).first.keys.toSet(),
          {'t', 'lat', 'lon', 'acc', 'v', 'h', 'alt', 'mock', 'bat'});
      // El hash es el del cuerpo canónico SIN hash ni firma.
      final sin = Map<String, dynamic>.from(j)..remove('hash')..remove('firma');
      expect(j['hash'], sha256Hex(jsonCanonico(sin)));
      // Y lo que se mandó ya es canónico: los bytes son exactamente los del lote guardado.
      expect(req.body, jsonCanonico(j));
      // Cuántos bytes pesa un lote de 40 puntos (se anota en RESUMEN-A).
      // ignore: avoid_print
      print('BYTES_LOTE_40=${utf8.encode(req.body).length}');
    });

    test('la cadena: el segundo lote lleva el hash del primero aceptado', () async {
      for (var i = 0; i < 80; i++) {
        await cola.agregar(_p(i), 1);
      }
      await e.intentar();
      expect(pedidos, hasLength(2));
      final a = jsonDecode(pedidos[0].body) as Map;
      final b = jsonDecode(pedidos[1].body) as Map;
      expect(b['hashAnterior'], a['hash']);
    });

    test('sin red: espera creciente con tope, y el reintento manda LOS MISMOS bytes', () async {
      for (var i = 0; i < 40; i++) {
        await cola.agregar(_p(i), 1);
      }
      respuestas.addAll([
        (_) => throw http.ClientException('sin red'),
      ]);
      final r1 = await e.intentar();
      expect(r1.que, 'reintentar');
      final espera1 = r1.proximoIntento!.difference(ahora);
      expect(espera1.inSeconds, inInclusiveRange(24, 36));
      // Antes de que venza la espera no sale nada: no se martilla.
      expect((await e.intentar()).que, 'esperando');
      expect(pedidos, hasLength(1));
      ahora = r1.proximoIntento!.add(const Duration(seconds: 1));
      respuestas.add((_) => http.Response('{"recibido":1,"sincronizadoHasta":1}', 200));
      final r2 = await e.intentar();
      expect(r2.que, 'enviado');
      expect(pedidos[1].body, pedidos[0].body, reason: 'mismo loteId, misma firma');
    });

    test('la espera crece y tiene techo de 30 minutos', () {
      final r = math.Random(3);
      expect(esperaTrasFallo(1, azar: r).inSeconds, inInclusiveRange(24, 36));
      expect(esperaTrasFallo(2, azar: r).inSeconds, inInclusiveRange(48, 72));
      expect(esperaTrasFallo(5, azar: r).inSeconds, inInclusiveRange(384, 576));
      expect(esperaTrasFallo(40, azar: r).inSeconds, inInclusiveRange(1440, 2160));
    });

    test('429 con Retry-After: se espera lo que dice la ingesta', () async {
      for (var i = 0; i < 40; i++) {
        await cola.agregar(_p(i), 1);
      }
      respuestas.add((_) => http.Response('{"message":"despacio"}', 429,
          headers: {'retry-after': '120'}));
      final r = await e.intentar();
      expect(r.que, 'reintentar');
      expect(r.codigo, 429);
      expect(r.proximoIntento!.difference(ahora), const Duration(seconds: 120));
      // Volver la red no borra un Retry-After.
      e.volvioLaRed();
      expect((await e.intentar()).que, 'esperando');
    });

    test('un 409/422 se da por rechazado y el siguiente lote encadena con el último ACEPTADO',
        () async {
      for (var i = 0; i < 80; i++) {
        await cola.agregar(_p(i), 1);
      }
      respuestas.add((_) => http.Response('{"message":"t futuro"}', 422));
      await e.intentar();
      expect(pedidos, hasLength(2));
      final b = jsonDecode(pedidos[1].body) as Map;
      expect(b['hashAnterior'], '0');
      final l = await cola.contarLotes();
      expect(l.rechazados, 1);
      expect(l.aceptados, 1);
    });

    test('401: re-registra la clave y reintenta el mismo lote; al tercero, rechazado', () async {
      var registros = 0;
      e = EmisorDeLotes(
        cola: cola,
        api: e.api,
        firmador: _Firmador(),
        instalacionId: 'inst-1',
        reloj: (g) async => RelojDelLote(mono: 1, arranques: 1, gnss: g),
        configuracion: () => config,
        loteSeg: () => 300,
        registrarClave: () async {
          registros++;
          await cola.escribir('claveRegistrada', 'si');
          return true;
        },
        ahora: () => ahora,
      );
      for (var i = 0; i < 40; i++) {
        await cola.agregar(_p(i), 1);
      }
      for (var k = 0; k < 3; k++) {
        respuestas.add((_) => http.Response('{"message":"firma"}', 401));
      }
      await e.intentar();
      ahora = ahora.add(const Duration(hours: 1));
      await e.intentar();
      ahora = ahora.add(const Duration(hours: 1));
      final r = await e.intentar();
      expect(r.que, 'rechazado');
      expect(registros, 2);
      expect(pedidos.map((p) => p.body).toSet(), hasLength(1));
    });

    test('409 cadena_rota: desarma el lote, toma el ultimoHash de la ingesta y reenvía los mismos puntos',
        () async {
      for (var i = 0; i < 40; i++) {
        await cola.agregar(_p(i), 1);
      }
      final suHash = 'ab' * 32;
      respuestas.add((_) => http.Response(
          jsonEncode({'ok': false, 'error': 'cadena_rota', 'ultimoHash': suHash, 'ultimoLoteId': 'x'}),
          409));
      final r = await e.intentar();
      expect(r.que, 'enviado');
      expect(pedidos, hasLength(2));
      final a = jsonDecode(pedidos[0].body) as Map, b = jsonDecode(pedidos[1].body) as Map;
      expect(a['hashAnterior'], '0');
      expect(b['hashAnterior'], suHash);
      expect(b['loteId'], isNot(a['loteId']));
      expect((b['puntos'] as List).first['t'], (a['puntos'] as List).first['t']);
      expect((await cola.contarLotes()).rechazados, 0);
    });

    test('409 en_proceso: se espera el Retry-After y se manda el MISMO lote', () async {
      for (var i = 0; i < 40; i++) {
        await cola.agregar(_p(i), 1);
      }
      respuestas.add((_) => http.Response('{"ok":false,"error":"en_proceso"}', 409,
          headers: {'retry-after': '5'}));
      final r = await e.intentar();
      expect(r.que, 'reintentar');
      ahora = ahora.add(const Duration(seconds: 6));
      expect((await e.intentar()).que, 'enviado');
      expect(pedidos[1].body, pedidos[0].body);
    });

    test('401 firma_invalida no se reintenta', () async {
      for (var i = 0; i < 40; i++) {
        await cola.agregar(_p(i), 1);
      }
      respuestas.add((_) => http.Response('{"ok":false,"error":"firma_invalida"}', 401));
      expect((await e.intentar()).que, 'rechazado');
      expect(pedidos, hasLength(1));
    });

    test('con atraso no pasa de 5 lotes por minuto (la ingesta corta en 6)', () async {
      for (var i = 0; i < 40 * 8; i++) {
        await cola.agregar(_p(i), 1);
      }
      final r = await e.intentar();
      expect(pedidos, hasLength(5));
      expect(r.que, 'esperando');
      ahora = ahora.add(const Duration(minutes: 1));
      await e.intentar();
      expect(pedidos, hasLength(8));
    });

    test('forzar arma con lo que haya (al detenerse)', () async {
      for (var i = 0; i < 3; i++) {
        await cola.agregar(_p(i), 1);
      }
      ahora = DateTime.fromMillisecondsSinceEpoch(_p(2).t + 1000);
      expect((await e.intentar()).que, 'nadaQueMandar');
      expect((await e.intentar(forzar: true)).que, 'enviado');
      expect((jsonDecode(pedidos.single.body)['puntos'] as List), hasLength(3));
    });
  });

  test('la ingesta la dice el servidor (rastreo.ingestaUrl); si no, la de la app', () {
    final api = ApiDeRastreo(llave: 'k', url: 'http://api:3085/api/v1', urlIngesta: 'http://local:8080');
    expect(api.baseIngesta, 'http://local:8080');
    api.usarIngestaDelServidor('http://10.0.2.2:8080/api/v1');
    expect(api.baseIngesta, 'http://10.0.2.2:8080');
    api.usarIngestaDelServidor('javascript:alert(1)');
    expect(api.baseIngesta, 'http://local:8080');
  });

  test('Retry-After como fecha HTTP', () {
    final ahora = DateTime.utc(2026, 9, 30, 12, 0, 0);
    expect(ApiDeRastreo.leerRetryAfter('Wed, 30 Sep 2026 12:01:30 GMT', ahora),
        const Duration(seconds: 90));
    expect(ApiDeRastreo.leerRetryAfter('basura', ahora), isNull);
  });
}
