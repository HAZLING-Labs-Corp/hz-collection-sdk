import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/src/rastreo/configuracion_de_rastreo.dart';
import 'package:hz_collection_sdk/src/rastreo/detector_de_movimiento.dart';

import 'cadencia_test.dart' show tablaDelContrato;

final _c = ConfiguracionDeRastreo.fromJson(
    {'activo': true, 'quietoMin': 5, 'arranqueKmh': 10, 'cadencia': tablaDelContrato});

/// Una lectura a [m] metros al norte del origen.
Lectura _l(int seg, double m, {double v = -1, double acc = 5}) => Lectura(
    t: 1000000 + seg * 1000, lat: 10.0 + m / 111195, lon: -66.9, acc: acc, v: v);

void main() {
  test('quieto → salió de la zona → confirmando → rodando con dos lecturas rápidas', () {
    final d = DetectorDeMovimiento(_c);
    expect(d.lectura(_l(0, 0), precisa: false).gpsPreciso, isFalse);
    // 100 m: todavía dentro de la zona.
    expect(d.lectura(_l(60, 100), precisa: false).estado, EstadoDeMovimiento.quieto);
    final sale = d.lectura(_l(120, 200), precisa: false);
    expect(sale.estado, EstadoDeMovimiento.confirmando);
    expect(sale.gpsPreciso, isTrue);
    expect(sale.motivo, 'salió de la zona');
    // Una lectura rápida no alcanza.
    expect(d.lectura(_l(125, 250, v: 8), precisa: true).estado, EstadoDeMovimiento.confirmando);
    final arranca = d.lectura(_l(130, 300, v: 8), precisa: true);
    expect(arranca.estado, EstadoDeMovimiento.rodando);
    expect(arranca.grabar, isTrue);
    expect(d.tramo, 1);
  });

  test('un salto del GPS con mala precisión no confirma', () {
    final d = DetectorDeMovimiento(_c)..lectura(_l(0, 0), precisa: false);
    d.actividad(TipoDeActividad.vehiculo, 1000000);
    expect(d.estado, EstadoDeMovimiento.confirmando);
    d.lectura(_l(1, 80, v: 80, acc: 120), precisa: true);
    d.lectura(_l(2, 160, v: 80, acc: 120), precisa: true);
    expect(d.estado, EstadoDeMovimiento.confirmando);
    // Y a los tres minutos se rinde.
    final r = d.tic(1000000 + 200 * 1000);
    expect(r.estado, EstadoDeMovimiento.quieto);
    expect(r.vaciar, isFalse);
  });

  test('rodando graba al ritmo de la fila «rodando» (10 s), y a los 5 min quieto apaga el GPS y vacía', () {
    final d = DetectorDeMovimiento(_c)..lectura(_l(0, 0), precisa: false);
    d.actividad(TipoDeActividad.vehiculo, 1000000);
    d.lectura(_l(1, 8, v: 8), precisa: true);
    d.lectura(_l(2, 16, v: 8), precisa: true);
    expect(d.estado, EstadoDeMovimiento.rodando);
    // El flujo entrega cada 5 s (la fila más rápida); a 29 km/h manda «rodando»: cada 10 s.
    final grabadas = <int>[];
    for (var s = 7; s <= 62; s += 5) {
      if (d.lectura(_l(s, s * 8.0, v: 8), precisa: true).grabar) grabadas.add(s);
    }
    expect(grabadas, [12, 22, 32, 42, 52, 62]);
    // Se detiene en el metro 500 y se queda ahí.
    Decision? ultima;
    for (var s = 67; s <= 62 + 5 * 60 + 5; s += 5) {
      ultima = d.lectura(_l(s, 500, v: 0), precisa: true);
      if (ultima.cambio) break;
    }
    expect(ultima!.estado, EstadoDeMovimiento.quieto);
    expect(ultima.gpsPreciso, isFalse);
    expect(ultima.vaciar, isTrue);
  });

  test('sobre 40 km/h la fila «rapido» graba cada 5 s, y al bajar vuelve a «rodando»', () {
    final d = DetectorDeMovimiento(_c)..lectura(_l(0, 0), precisa: false);
    d.actividad(TipoDeActividad.vehiculo, 1000000);
    d.lectura(_l(1, 20, v: 20), precisa: true);
    d.lectura(_l(2, 40, v: 20), precisa: true);
    expect(d.fila.estado, 'rapido');
    expect(d.intervalo, const Duration(seconds: 5));
    final baja = d.lectura(_l(7, 90, v: 8), precisa: true);
    expect(baja.fila.estado, 'rodando');
    expect(baja.cambioDeFila, isTrue);
  });

  test('quieto: la fila pasa a «detenido» después de 5 min sin moverse', () {
    final d = DetectorDeMovimiento(_c)..lectura(_l(0, 0), precisa: false);
    d.actividad(TipoDeActividad.vehiculo, 1000000);
    d.lectura(_l(1, 8, v: 8), precisa: true);
    d.lectura(_l(2, 16, v: 8), precisa: true);
    final q = d.tic(1000000 + 2000 + 5 * 60000);
    expect(q.estado, EstadoDeMovimiento.quieto);
    expect(d.tic(1000000 + 2000 + 5 * 60000 + 1000).fila.estado, 'detenido');
    expect(d.fila.muestreoSeg, 0);
  });

  test('un hueco dentro del tramo se informa', () {
    final d = DetectorDeMovimiento(_c)..lectura(_l(0, 0), precisa: false);
    d.actividad(TipoDeActividad.vehiculo, 1000000);
    d.lectura(_l(1, 8, v: 8), precisa: true);
    d.lectura(_l(2, 16, v: 8), precisa: true);
    final r = d.lectura(_l(92, 900, v: 8), precisa: true);
    expect(r.grabar, isTrue);
    expect(r.hueco, (1000000 + 2000, 1000000 + 92000));
  });

  test('sin lecturas mientras rodaba, el tic lo pasa a quieto', () {
    final d = DetectorDeMovimiento(_c)..lectura(_l(0, 0), precisa: false);
    d.actividad(TipoDeActividad.vehiculo, 1000000);
    d.lectura(_l(1, 8, v: 8), precisa: true);
    d.lectura(_l(2, 16, v: 8), precisa: true);
    expect(d.tic(1000000 + 2000 + 4 * 60000).estado, EstadoDeMovimiento.rodando);
    final r = d.tic(1000000 + 2000 + 5 * 60000);
    expect(r.estado, EstadoDeMovimiento.quieto);
    expect(r.vaciar, isTrue);
  });
}
