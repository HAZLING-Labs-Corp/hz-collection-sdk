import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hz_collection_sdk/src/rastreo/api_de_rastreo.dart';
import 'package:hz_collection_sdk/src/rastreo/pulso_por_presencia.dart';

const _ahora = 1000000;

class _Banco {
  final posts = <Map<String, dynamic>>[];
  int respondeCon = 202;
  late final ApiDeRastreo api = ApiDeRastreo(
    llave: 'k',
    url: 'http://x',
    cliente: MockClient((req) async {
      posts.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{"ok":true}', respondeCon);
    }),
  );
  int fixes = 0;
  bool apagado = false;
  Future<Map<String, dynamic>?> Function()? fix;

  late final PulsoPorPresencia pulso = PulsoPorPresencia(
    ahora: () => _ahora,
    apagado: () => apagado,
    enviarPresencia: api.enviarPresencia,
    timeout: const Duration(milliseconds: 100),
    tomarPosicion: () async {
      fixes++;
      if (fix != null) return fix!();
      return {'instalacionId': 'i1', 't': _ahora, 'lat': 10.5, 'lon': -66.9, 'acc': 5.0};
    },
  );
}

RespuestaDeIngesta _r(String cuerpo, {int codigo = 202}) => RespuestaDeIngesta(codigo: codigo, cuerpo: cuerpo);
String _conPulso(String id, int hasta) => jsonEncode({'ok': true, 'pulso': {'id': id, 'hasta': hasta}});

void main() {
  test('con pulso vigente toma una posición y manda presencia con origen y pulsoId', () async {
    final b = _Banco();
    expect(await b.pulso.alResponder(_r(_conPulso('p1', _ahora + 60000))), isTrue);
    expect(b.fixes, 1);
    expect(b.posts, hasLength(1));
    expect(b.posts.single['origen'], 'pulso');
    expect(b.posts.single['pulsoId'], 'p1');
    expect(b.posts.single['lat'], 10.5);
  });

  test('idempotente: el mismo id una sola vez', () async {
    final b = _Banco();
    await b.pulso.alResponder(_r(_conPulso('p1', _ahora + 60000)));
    expect(await b.pulso.alResponder(_r(_conPulso('p1', _ahora + 60000))), isFalse);
    expect(b.posts, hasLength(1));
    expect(b.fixes, 1);
    expect(await b.pulso.alResponder(_r(_conPulso('p2', _ahora + 60000))), isTrue);
    expect(b.posts, hasLength(2));
  });

  test('pulso vencido no se atiende', () async {
    final b = _Banco();
    expect(await b.pulso.alResponder(_r(_conPulso('p1', _ahora - 1))), isFalse);
    expect(await b.pulso.alResponder(_r(_conPulso('p1', _ahora))), isFalse);
    expect(b.fixes, 0);
    expect(b.posts, isEmpty);
  });

  test('captura apagada por el servidor: no responde', () async {
    final b = _Banco()..apagado = true;
    expect(await b.pulso.alResponder(_r(_conPulso('p1', _ahora + 60000))), isFalse);
    expect(b.fixes, 0);
    expect(b.posts, isEmpty);
  });

  test('se apaga mientras espera el fix: no manda', () async {
    final b = _Banco();
    b.fix = () async {
      b.apagado = true;
      return {'t': _ahora, 'lat': 1.0, 'lon': 2.0};
    };
    expect(await b.pulso.alResponder(_r(_conPulso('p1', _ahora + 60000))), isFalse);
    expect(b.posts, isEmpty);
  });

  test('respuestas sin pulso, mal formadas o no 2xx se ignoran', () async {
    final b = _Banco();
    for (final r in [
      _r('{"ok":true}'),
      _r('no es json'),
      _r('{"pulso":{"id":"p","hasta":"x"}}'),
      _r('{"pulso":{"hasta":9999999}}'),
      _r('{"pulso":"p"}'),
      _r(_conPulso('p1', _ahora + 1000), codigo: 500),
      const RespuestaDeIngesta(error: 'sin red'),
    ]) {
      expect(await b.pulso.alResponder(r), isFalse);
    }
    expect(b.fixes, 0);
    expect(b.posts, isEmpty);
  });

  test('sin posición o con timeout: no manda, no tira, y el id no se reintenta', () async {
    final b = _Banco();
    b.fix = () async => null;
    expect(await b.pulso.alResponder(_r(_conPulso('p1', _ahora + 60000))), isFalse);
    expect(b.pulso.ultimoProblema, contains('sin posición'));
    b.fix = () => Completer<Map<String, dynamic>?>().future; // nunca llega
    expect(await b.pulso.alResponder(_r(_conPulso('p2', _ahora + 60000))), isFalse);
    expect(b.posts, isEmpty);
    expect(await b.pulso.alResponder(_r(_conPulso('p1', _ahora + 60000))), isFalse);
    expect(b.fixes, 2);
  });

  test('si el servidor rechaza la presencia del pulso, no cuenta como respondido', () async {
    final b = _Banco()..respondeCon = 403;
    expect(await b.pulso.alResponder(_r(_conPulso('p1', _ahora + 60000))), isFalse);
    expect(b.posts, hasLength(1));
    expect(b.pulso.respondidos, 0);
  });

  test('el pulso se lee del cuerpo entero aunque pase de 500 caracteres', () async {
    final b = _Banco();
    final largo = '{"ok":true,"relleno":"${'x' * 800}","pulso":{"id":"p-largo","hasta":${_ahora + 60000}}}';
    final r = RespuestaDeIngesta(
        codigo: 202, cuerpo: '${largo.substring(0, 500)}…', cuerpoCompleto: largo);
    expect(await b.pulso.alResponder(r), isTrue);
    expect(b.posts.single['pulsoId'], 'p-largo');
  });
}
