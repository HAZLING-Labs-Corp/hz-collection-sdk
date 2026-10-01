import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hz_collection_sdk/src/rastreo/api_de_rastreo.dart';
import 'package:hz_collection_sdk/src/rastreo/cola_de_rastreo.dart' show Hueco;
import 'package:hz_collection_sdk/src/rastreo/configuracion_de_rastreo.dart';
import 'package:hz_collection_sdk/src/rastreo/golpe/detector_de_golpe.dart';
import 'package:hz_collection_sdk/src/rastreo/golpe/sucesos_del_aparato.dart';
import 'package:hz_collection_sdk/src/rastreo/lote.dart';
import 'package:hz_collection_sdk/src/rastreo/punto.dart';
import 'package:hz_collection_sdk/src/rastreo/sin_gps.dart';

const _t0 = 1727700000000;
const _u = UmbralesDeGolpe();

/// Pasa las muestras por el detector y devuelve lo que concluyó.
List<GolpeDetectado> _correr(DetectorDeGolpe d, List<MuestraDeAceleracion> ms,
    {double? vGps, int cadaMsGps = 1000}) {
  final out = <GolpeDetectado>[];
  var ultimoGps = 0;
  for (final m in ms) {
    if (vGps != null && m.t - ultimoGps >= cadaMsGps) {
      d.velocidad(vGps, m.t);
      ultimoGps = m.t;
    }
    final g = d.muestra(m);
    if (g != null) out.add(g);
  }
  return out;
}

PuntoDeRastreo _p(int i) => PuntoDeRastreo(
    t: _t0 + i * 1000, lat: 10.49, lon: -66.87, acc: 5, v: 0, h: 90, alt: 900, mock: false, bat: 80);

void main() {
  group('el detector de golpe', () {
    test('pico y después quietud: un solo golpe_quietud, con la hora del pico', () {
      final d = DetectorDeGolpe(_u);
      final ms = DetectorDeGolpe.muestrasDeGolpe(desde: _t0, umbrales: _u);
      final r = _correr(d, ms);
      expect(r, hasLength(1));
      // el pico es la primera muestra a ≥ 4 g: después de 2 s rodando a 20 Hz
      expect(r.single.t, _t0 + 2000);
      expect(r.single.pico, closeTo(6, 0.01));
      expect(r.single.confianza, inInclusiveRange(0.5, 1.0));
      expect(r.single.conGps, isFalse);
    });

    test('un pico sin quietud es un bache: no emite nada', () {
      final d = DetectorDeGolpe(_u);
      final ms = DetectorDeGolpe.muestrasDeGolpe(desde: _t0, umbrales: _u, quietudDespues: false);
      expect(_correr(d, ms), isEmpty);
      expect(d.fase, FaseDelGolpe.vigilando);
    });

    test('por debajo de gPico no pasa nada', () {
      final d = DetectorDeGolpe(_u);
      final ms = DetectorDeGolpe.muestrasDeGolpe(desde: _t0, umbrales: _u, pico: 3.5);
      expect(_correr(d, ms), isEmpty);
    });

    test('teléfono quieto pero el GPS dice que sigue andando: bache (no emite)', () {
      final d = DetectorDeGolpe(_u);
      final ms = DetectorDeGolpe.muestrasDeGolpe(desde: _t0, umbrales: _u);
      expect(_correr(d, ms, vGps: 8), isEmpty);
    });

    test('con el GPS en ~0 la quietud queda confirmada y la confianza sube', () {
      final ms = DetectorDeGolpe.muestrasDeGolpe(desde: _t0, umbrales: _u);
      final sin = _correr(DetectorDeGolpe(_u), ms).single;
      final con = _correr(DetectorDeGolpe(_u), ms, vGps: 0.2).single;
      expect(con.conGps, isTrue);
      expect(con.confianza, greaterThan(sin.confianza));
    });

    test('un bloque que se mueve en medio de la quietud la invalida', () {
      final d = DetectorDeGolpe(_u);
      final ms = DetectorDeGolpe.muestrasDeGolpe(desde: _t0, umbrales: _u);
      // a los 30 s del pico, 5 s de caminar (dispersión 0,3 g)
      final mitad = _t0 + 2000 + 30000;
      final alterado = [
        for (final m in ms)
          (m.t >= mitad && m.t < mitad + 5000)
              ? MuestraDeAceleracion(t: m.t, x: 0, y: 0, z: (m.t ~/ 50).isEven ? 1.4 * gravedad : 0.6 * gravedad)
              : m,
      ];
      expect(_correr(d, alterado), isEmpty);
    });

    test('antirebote: el mismo golpe que sigue rebotando no da dos sucesos', () {
      final d = DetectorDeGolpe(_u);
      final a = DetectorDeGolpe.muestrasDeGolpe(desde: _t0, umbrales: _u);
      final fin = a.last.t;
      // otro golpe entero 10 s después: cae en el antirebote
      final b = DetectorDeGolpe.muestrasDeGolpe(desde: fin + 10000, umbrales: _u, semilla: 3);
      expect(_correr(d, [...a, ...b]), hasLength(1));
      expect(d.fase, FaseDelGolpe.antirebote);
      // pasado el antirebote, un golpe nuevo sí cuenta
      final c = DetectorDeGolpe.muestrasDeGolpe(
          desde: fin + DetectorDeGolpe.antirebote.inMilliseconds + 1000, umbrales: _u, semilla: 5);
      expect(_correr(d, c), hasLength(1));
    });

    test('la quietud dura lo que diga quietudSeg', () {
      const corto = UmbralesDeGolpe(gPico: 4, quietudSeg: 20);
      final d = DetectorDeGolpe(corto);
      final ms = DetectorDeGolpe.muestrasDeGolpe(desde: _t0, umbrales: corto);
      final r = <(int, GolpeDetectado)>[];
      for (final m in ms) {
        final g = d.muestra(m);
        if (g != null) r.add((m.t, g));
      }
      expect(r, hasLength(1));
      final esperado = _t0 + 2000 + DetectorDeGolpe.asentamiento.inMilliseconds + 20000;
      expect(r.single.$1, inInclusiveRange(esperado, esperado + 200));
    });

    test('sin muestras con qué juzgar la quietud no afirma nada', () {
      final d = DetectorDeGolpe(_u);
      // pico, y después dos muestras sueltas separadas por más de la quietud
      expect(d.muestra(const MuestraDeAceleracion(t: _t0, x: 0, y: 0, z: 6 * gravedad)), isNull);
      expect(d.muestra(const MuestraDeAceleracion(t: _t0 + 4000, x: 0, y: 0, z: gravedad)), isNull);
      expect(d.muestra(const MuestraDeAceleracion(t: _t0 + 70000, x: 0, y: 0, z: gravedad)), isNull);
      expect(d.fase, FaseDelGolpe.vigilando);
    });

    test('la confianza: 0,5 en el umbral, 1 al doble con quietud total y GPS', () {
      final d = DetectorDeGolpe(_u);
      expect(d.confianzaDe(4, 0, true), 0.5);
      expect(d.confianzaDe(8, 0, true), 1.0);
      expect(d.confianzaDe(20, 0, true), 1.0);
      expect(d.confianzaDe(8, DetectorDeGolpe.dispersionMaxima, false), closeTo(0.43, 0.01));
    });
  });

  group('los umbrales', () {
    test('sin bloque: 4 g y 60 s', () {
      final u = UmbralesDeGolpe.fromJson(null);
      expect(u.gPico, 4);
      expect(u.quietudSeg, 60);
    });
    test('el piso y el techo', () {
      final u = UmbralesDeGolpe.fromJson({'g': 0.5, 'quietoSeg': 100000});
      expect(u.gPico, UmbralesDeGolpe.pisoGPico);
      expect(u.quietudSeg, UmbralesDeGolpe.techoQuietudSeg);
      final v = UmbralesDeGolpe.fromJson({'g': 99, 'quietoSeg': 1});
      expect(v.gPico, UmbralesDeGolpe.techoGPico);
      expect(v.quietudSeg, UmbralesDeGolpe.pisoQuietudSeg);
    });
    test('acepta también los nombres de la política del servidor (gPico, quietudSeg)', () {
      final u = UmbralesDeGolpe.fromJson({'gPico': 5, 'quietudSeg': 30});
      expect(u.gPico, 5);
      expect(u.quietudSeg, 30);
    });
    test('viajan en el bloque rastreo y sobreviven al disco', () {
      final c = ConfiguracionDeRastreo.fromJson({'activo': true, 'golpe': {'g': 5, 'quietoSeg': 45}});
      expect(c.golpe.gPico, 5);
      expect(c.golpe.quietudSeg, 45);
      final otra = ConfiguracionDeRastreo.fromJson(c.toJson());
      expect(otra.golpe.gPico, 5);
      expect(otra.golpe.quietudSeg, 45);
      expect(ConfiguracionDeRastreo.fromJson({'activo': true}).golpe.gPico, 4);
    });
  });

  group('el suceso', () {
    test('el id es el SHA-256 hex de instalacionId|tipo|t (el mismo que valida la ingesta)', () {
      expect(idDelSuceso('inst-12345678', 'golpe_quietud', _t0),
          '1c26cccf7a95dc55b9f2899bdc2eb47ef26725b8d78fd3013b031a720a2bcc53');
    });

    test('lleva los últimos 10 puntos, cada uno con sus 9 campos', () {
      final s = SucesoDelAparato(
          instalacionId: 'inst-12345678', tipo: TipoDeSuceso.golpeQuietud, t: _t0, confianza: 0.876,
          puntos: [for (var i = 0; i < 14; i++) _p(i)]);
      final j = s.toJson();
      expect(j.keys.toSet(), {'instalacionId', 'id', 'tipo', 't', 'confianza', 'puntos'});
      expect(j['confianza'], 0.88);
      final pts = j['puntos'] as List;
      expect(pts, hasLength(10));
      expect((pts.first as Map)['t'], _t0 + 4000);
      expect((pts.first as Map).keys.toSet(), {'t', 'lat', 'lon', 'acc', 'v', 'h', 'alt', 'mock', 'bat'});
    });

    test('sin puntos, la clave no va', () {
      final s = SucesoDelAparato(instalacionId: 'inst-12345678', tipo: 'golpe_quietud', t: _t0, confianza: 2);
      expect(s.toJson().containsKey('puntos'), isFalse);
      expect(s.confianza, 1.0);
    });
  });

  group('el emisor de sucesos', () {
    late String? guardado;
    late List<int?> codigos;
    late List<Map<String, dynamic>> recibidos;
    var ahora = DateTime.fromMillisecondsSinceEpoch(_t0 + 60000);

    EmisorDeSucesos nuevo() => EmisorDeSucesos(
          api: ApiDeRastreo(
            llave: 'llave-de-prueba',
            url: 'http://ingesta.test',
            cliente: MockClient((req) async {
              expect(req.url.path, '/api/v1/rastreo/sucesos');
              final c = codigos.removeAt(0);
              if (c == null) throw http.ClientException('sin red');
              recibidos.add(jsonDecode(req.body) as Map<String, dynamic>);
              return http.Response(c == 429 ? '{"error":"ritmo_excedido"}' : '{}', c,
                  headers: c == 429 ? {'retry-after': '30'} : {});
            }),
          ),
          leer: () async => guardado,
          escribir: (v) async => guardado = v,
          ahora: () => ahora,
        );

    SucesoDelAparato s(int t) => SucesoDelAparato(
        instalacionId: 'inst-12345678', tipo: 'golpe_quietud', t: t, confianza: 0.9, puntos: [_p(0)]);

    setUp(() {
      guardado = null;
      codigos = [];
      recibidos = [];
      ahora = DateTime.fromMillisecondsSinceEpoch(_t0 + 60000);
    });

    test('202: sale en el acto y deja la cola vacía', () async {
      codigos = [202];
      final r = await nuevo().encolarYEnviar(s(_t0));
      expect(r.entregados, 1);
      expect(r.pendientes, 0);
      expect(guardado, isNull);
      expect(recibidos.single['id'], idDelSuceso('inst-12345678', 'golpe_quietud', _t0));
    });

    test('sin red: queda en la cola persistente, espera, y un 200 al reintentar cuenta como entregado', () async {
      codigos = [null];
      final e = nuevo();
      final r = await e.encolarYEnviar(s(_t0));
      expect(r.pendientes, 1);
      expect(r.proximoIntento, isNotNull);
      expect(e.fallosSeguidos, 1);
      // otro proceso (la app se mató y volvió) ve la cola en el disco
      final e2 = nuevo();
      expect((await e2.pendientes()).single.id, idDelSuceso('inst-12345678', 'golpe_quietud', _t0));
      // mientras espera, no toca la red
      final quieto = await e.intentar();
      expect(quieto.entregados, 0);
      expect(codigos, isEmpty);
      // pasa la espera: 200 (ya lo tenía) → entregado
      ahora = ahora.add(const Duration(minutes: 1));
      codigos = [200];
      final r2 = await e.intentar();
      expect(r2.entregados, 1);
      expect(guardado, isNull);
    });

    test('la espera crece con jitter completo y tiene techo', () async {
      final e = nuevo();
      codigos = [null];
      await e.encolarYEnviar(s(_t0));
      for (var i = 0; i < 12; i++) {
        ahora = e.proximoIntento!.add(const Duration(milliseconds: 1));
        codigos = [null];
        await e.intentar();
        expect(e.proximoIntento!.difference(ahora), lessThanOrEqualTo(const Duration(minutes: 30)));
      }
      expect(e.fallosSeguidos, 13);
    });

    test('429: obedece Retry-After (más azar)', () async {
      codigos = [429];
      final e = nuevo();
      final r = await e.encolarYEnviar(s(_t0));
      expect(r.pendientes, 1);
      final espera = r.proximoIntento!.difference(ahora);
      expect(espera, greaterThanOrEqualTo(const Duration(seconds: 30)));
      expect(espera, lessThanOrEqualTo(const Duration(seconds: 60)));
    });

    test('400: se descarta (los mismos bytes darían lo mismo)', () async {
      codigos = [400];
      final r = await nuevo().encolarYEnviar(s(_t0));
      expect(r.descartados, 1);
      expect(r.pendientes, 0);
    });

    test('el mismo suceso dos veces es uno solo en la cola', () async {
      codigos = [null];
      final e = nuevo();
      await e.encolarYEnviar(s(_t0));
      codigos = [null];
      await e.encolarYEnviar(s(_t0));
      expect(await e.pendientes(), hasLength(1));
    });

    test('un suceso nuevo salta la espera de los viejos y salen los dos', () async {
      codigos = [null];
      final e = nuevo();
      await e.encolarYEnviar(s(_t0));
      codigos = [202, 202];
      final r = await e.encolarYEnviar(s(_t0 + 5000));
      expect(r.entregados, 2);
      expect(r.pendientes, 0);
    });

    test('lo de más de 48 h se olvida', () async {
      codigos = [null];
      final e = nuevo();
      await e.encolarYEnviar(s(_t0));
      ahora = ahora.add(const Duration(hours: 49));
      final r = await e.intentar();
      expect(r.pendientes, 0);
      expect(codigos, isEmpty);
    });
  });

  group('el medio declarado en el lote', () {
    final reloj = const RelojDelLote(mono: 1, arranques: 1);
    test('va en el cuerpo firmado si se declaró', () {
      final m = cuerpoSinFirmar(
          instalacionId: 'i', loteId: 'l', claveId: 'c', hashAnterior: '0', reloj: reloj, puntos: [_p(0)], medio: 'carro');
      expect(m['medio'], 'carro');
    });
    test('sin declarar, la clave no va (el lote es el mismo de antes)', () {
      final m = cuerpoSinFirmar(
          instalacionId: 'i', loteId: 'l', claveId: 'c', hashAnterior: '0', reloj: reloj, puntos: [_p(0)]);
      expect(m.containsKey('medio'), isFalse);
    });
  });

  group('por qué no hay GPS', () {
    test('el orden: permiso, GPS apagado, sin fix', () {
      expect(clasificarSinGps(permisoConcedido: false, gpsPrendido: false, moviendose: true, msDesdeElUltimoPunto: 0),
          MotivoSinGps.permisoRevocado);
      expect(clasificarSinGps(permisoConcedido: true, gpsPrendido: false, moviendose: false, msDesdeElUltimoPunto: 0),
          MotivoSinGps.gpsApagado);
      expect(clasificarSinGps(permisoConcedido: true, gpsPrendido: true, moviendose: true, msDesdeElUltimoPunto: 90000),
          MotivoSinGps.sinFix);
      expect(clasificarSinGps(permisoConcedido: true, gpsPrendido: true, moviendose: true, msDesdeElUltimoPunto: 5000),
          isNull);
      // quieto, el GPS preciso está apagado a propósito: no es «sin fix»
      expect(clasificarSinGps(permisoConcedido: true, gpsPrendido: true, moviendose: false, msDesdeElUltimoPunto: null),
          isNull);
    });

    test('el motivo de un hueco es el del rato que más se le cruza; si ninguno, sin fix', () {
      final r = RegistroSinGps();
      r.anotar(MotivoSinGps.gpsApagado, 1000);
      r.anotar(MotivoSinGps.permisoRevocado, 5000);
      r.anotar(null, 6000);
      expect(r.vigente, isNull);
      expect(r.motivoDe(const Hueco(1500, 6500, 1)), MotivoSinGps.gpsApagado);
      expect(r.motivoDe(const Hueco(4900, 6500, 1)), MotivoSinGps.permisoRevocado);
      expect(r.motivoDe(const Hueco(10000, 20000, 1)), MotivoSinGps.sinFix);
      r.anotar(MotivoSinGps.sinFix, 30000);
      r.anotar(MotivoSinGps.sinFix, 31000);
      expect(r.tramos, hasLength(3));
      expect(r.vigente, MotivoSinGps.sinFix);
    });
  });
}
