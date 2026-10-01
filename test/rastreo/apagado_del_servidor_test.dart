import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hz_collection_sdk/src/rastreo/apagado_del_servidor.dart';
import 'package:hz_collection_sdk/src/rastreo/api_de_rastreo.dart';

/// Un reloj de mentira: guarda lo programado y lo dispara a mano.
class _Reloj {
  final esperas = <Duration>[];
  final pendientes = <void Function()>[];
  int cancelados = 0;
  void Function() programar(Duration d, void Function() f) {
    esperas.add(d);
    pendientes.add(f);
    return () => cancelados++;
  }

  Future<void> disparar() async {
    final f = pendientes.removeLast();
    f();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('esApagadoDelServidor: sólo 403 con rastreo_apagado o medicion_apagada', () {
    expect(esApagadoDelServidor(403, 'rastreo_apagado'), isTrue);
    expect(esApagadoDelServidor(403, 'medicion_apagada'), isTrue);
    expect(esApagadoDelServidor(403, 'sin_alcance'), isFalse);
    expect(esApagadoDelServidor(401, 'rastreo_apagado'), isFalse);
    expect(esApagadoDelServidor(403, null), isFalse);
  });

  test('la espera de relectura crece al doble desde 1 min, con techo de 1 h, y nunca es 0', () {
    expect(topeDeRelectura(1), const Duration(minutes: 1));
    expect(topeDeRelectura(2), const Duration(minutes: 2));
    expect(topeDeRelectura(4), const Duration(minutes: 8));
    expect(topeDeRelectura(7), const Duration(hours: 1));
    expect(topeDeRelectura(40), const Duration(hours: 1));
    final azar = math.Random(3);
    for (var i = 1; i < 10; i++) {
      final e = esperaDeRelectura(i, azar);
      expect(e >= topeDeRelectura(i) ~/ 2 && e <= topeDeRelectura(i), isTrue, reason: 'intento $i: $e');
    }
  });

  test('vigía: apagar → relee con espera creciente; mientras siga apagado, no vuelve; al volver activo, retoma UNA vez', () async {
    final reloj = _Reloj();
    final respuestas = <bool?>[false, null, false, true];
    var relecturas = 0, vueltas = 0;
    final v = VigiaDelApagado(
      releerActivo: () async {
        relecturas++;
        return respuestas.removeAt(0);
      },
      alVolver: () async => vueltas++,
      programar: reloj.programar,
      azar: math.Random(1),
    );
    v.apagar('medicion_apagada');
    v.apagar('medicion_apagada'); // un segundo 403 no reinicia la espera
    expect(v.apagado, isTrue);
    expect(v.motivo, 'medicion_apagada');
    expect(reloj.esperas, hasLength(1));
    for (var i = 0; i < 3; i++) {
      await reloj.disparar(); // false, sin respuesta (null), false: sigue apagado
      expect(v.apagado, isTrue);
      expect(vueltas, 0);
    }
    expect(reloj.esperas, hasLength(4));
    for (var i = 1; i < reloj.esperas.length; i++) {
      expect(reloj.esperas[i] <= topeDeRelectura(i + 1) && reloj.esperas[i] >= topeDeRelectura(i + 1) ~/ 2, isTrue);
    }
    expect(reloj.esperas.last > reloj.esperas.first, isTrue, reason: 'la espera crece');
    await reloj.disparar(); // true: retoma
    expect(v.apagado, isFalse);
    expect(vueltas, 1);
    expect(relecturas, 4);
    expect(reloj.pendientes, isEmpty, reason: 'encendido, no se programa otra relectura');
    await v.encender();
    expect(vueltas, 1, reason: 'encender dos veces no retoma dos veces');
  });

  test('vigía: la relectura de cada hora también enciende (y cancela la programada)', () async {
    final reloj = _Reloj();
    var vueltas = 0;
    final v = VigiaDelApagado(releerActivo: () async => false, alVolver: () async => vueltas++, programar: reloj.programar);
    v.apagar('rastreo_apagado');
    await v.encender();
    expect(v.apagado, isFalse);
    expect(vueltas, 1);
    expect(reloj.cancelados, 1);
  });

  test('leerConfiguracion manda la instalación (configuración efectiva de ESTE aparato)', () async {
    late Uri pedido;
    final api = ApiDeRastreo(
      llave: 'pk_prueba',
      url: 'http://api',
      cliente: MockClient((r) async {
        pedido = r.url;
        return http.Response('{"rastreo":{"activo":false}}', 200);
      }),
    );
    final (bloque, r) = await api.leerConfiguracion('com.app', instalacionId: 'inst-123');
    expect(r.codigo, 200);
    expect(bloque!['activo'], false);
    expect(pedido.queryParameters, {'paquete': 'com.app', 'instalacionId': 'inst-123'});
    await api.leerConfiguracion('com.app');
    expect(pedido.queryParameters, {'paquete': 'com.app'}, reason: 'sin instalación, como antes');
  });
}
