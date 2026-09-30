import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/src/rastreo/configuracion_de_rastreo.dart';

import 'cadencia_test.dart' show tablaDelContrato;

void main() {
  test('la forma de PM-025 §4.5 (con la tabla de cadencia) se lee campo por campo', () {
    final c = ConfiguracionDeRastreo.fromJson({
      'activo': true,
      'perfil': 'persona-en-movimiento',
      'arranqueKmh': 10,
      'quietoMin': 5,
      'golpe': {'g': 4, 'quietoSeg': 60},
      'estadoForzado': null,
      'lotePuntos': 40,
      'cadencia': tablaDelContrato,
    });
    expect(c.activo, isTrue);
    expect(c.perfil, 'persona-en-movimiento');
    expect(c.quietoMin, 5);
    expect(c.arranqueKmh, 10);
    expect(c.lotePuntos, 40);
    expect(c.estadoForzado, isNull);
    expect(c.cadencia, hasLength(5));
  });

  test('sin bloque, o con activo distinto de true, queda apagado', () {
    expect(ConfiguracionDeRastreo.fromJson(null).activo, isFalse);
    expect(ConfiguracionDeRastreo.fromJson({'activo': 'true'}).activo, isFalse);
    expect(ConfiguracionDeRastreo.fromJson({'activo': false, 'perfil': null}).activo, isFalse);
  });

  test('un número roto no deja al teléfono martillando la ingesta', () {
    final c = ConfiguracionDeRastreo.fromJson({
      'activo': true,
      'lotePuntos': 100000,
      'quietoMin': -3,
      'arranqueKmh': 'diez',
    });
    expect(c.lotePuntos, ConfiguracionDeRastreo.techoLotePuntos);
    expect(c.quietoMin, ConfiguracionDeRastreo.pisoQuietoMin);
    expect(c.arranqueKmh, 10);
  });

  test('lo que se guarda se vuelve a leer igual (tabla incluida)', () {
    final c = ConfiguracionDeRastreo.fromJson(
        {'activo': true, 'perfil': 'a-pie', 'cadencia': tablaDelContrato});
    final d = ConfiguracionDeRastreo.fromJson(c.toJson());
    expect(d.toJson(), c.toJson());
    expect(d.cadencia[3].si.horaEntre, (22 * 60, 6 * 60));
  });
}
