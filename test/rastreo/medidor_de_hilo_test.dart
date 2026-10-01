import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/src/rastreo/canonico.dart';
import 'package:hz_collection_sdk/src/rastreo/lote.dart';
import 'package:hz_collection_sdk/src/rastreo/medidor_de_hilo.dart';
import 'package:hz_collection_sdk/src/rastreo/punto.dart';

class _Firmador implements FirmadorDeLotes {
  @override
  String get claveId => 'cd' * 32;
  @override
  Future<String> firmar(List<int> bytes) async => base64.encode(utf8.encode(sha256Hex('x')));
}

void main() {
  tearDown(() {
    MedidorDeHilo.activo = false;
    MedidorDeHilo.olvidar();
  });

  test('apagado no anota nada', () async {
    expect(MedidorDeHilo.sincrono('x', () => 1), 1);
    expect(await MedidorDeHilo.asincrono('y', () async => 2), 2);
    expect(MedidorDeHilo.resumen(), isEmpty);
  });

  test('prendido separa lo que BLOQUEA (Dart de corrido) de lo que espera (la firma nativa)',
      () async {
    MedidorDeHilo.activo = true;
    final puntos = [
      for (var i = 0; i < 40; i++)
        PuntoDeRastreo(
            t: 1727700000000 + i * 10000, lat: 10.4912837 + i * 1e-4, lon: -66.8791234,
            acc: 4.5, v: 8.33, h: 84.2, alt: 918, mock: false, bat: 80)
    ];
    for (var i = 0; i < 50; i++) {
      await armarLote(
          instalacionId: 'inst', loteId: nuevoUuid(), hashAnterior: '0',
          reloj: const RelojDelLote(mono: 1, arranques: 1), puntos: puntos,
          firmador: _Firmador());
    }
    final r = MedidorDeHilo.resumen();
    // ignore: avoid_print
    print('MEDIDOR_HOST ${r.join(' | ')}');
    expect(r.firstWhere((l) => l.startsWith('lote.canonico+sha256(40)')), contains('BLOQUEA'));
    expect(r.firstWhere((l) => l.startsWith('lote.firmar(nativo)')), contains('espera'));
  });
}
