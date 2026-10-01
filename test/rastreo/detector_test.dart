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
  pruebasDeRuido();
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

// ── Ruido de mesa (2026-10-01): el SDK no puede quedarse «rodando» quieto ──
DetectorDeMovimiento _rodando() {
  final d = DetectorDeMovimiento(_c)..lectura(_l(0, 0), precisa: false);
  d.actividad(TipoDeActividad.vehiculo, 1000000);
  d.lectura(_l(1, 8, v: 8), precisa: true);
  d.lectura(_l(2, 16, v: 8), precisa: true);
  expect(d.estado, EstadoDeMovimiento.rodando);
  return d;
}

void pruebasDeRuido() {
  test('ruido de mesa (acc 5-30, v 0-1,5, oscila unos metros) pasa a quieto en quietoMin', () {
    final d = _rodando();
    var cayo = -1;
    var apagoGps = false;
    for (var s = 3; s <= 420; s += 3) {
      final ruido = (s * 7 % 11) - 5.0; // -5..5 m
      final r = d.lectura(
          _l(s, 16 + ruido, v: (s % 4) * 0.5, acc: 5 + (s * 13 % 26).toDouble()),
          precisa: true);
      if (r.estado == EstadoDeMovimiento.quieto) {
        cayo = s;
        apagoGps = !r.gpsPreciso && r.vaciar;
        break;
      }
    }
    expect(cayo, greaterThan(0), reason: 'tenía que pasar a quieto');
    expect(cayo, lessThanOrEqualTo(2 + 300 + 10));
    expect(cayo, greaterThanOrEqualTo(2 + 300 - 5));
    expect(apagoGps, isTrue);
  });

  test('caminar lento real (0,6 m/s hacia un lado) sigue rodando', () {
    final d = _rodando();
    for (var s = 3; s <= 900; s += 3) {
      final r = d.lectura(_l(s, 16 + s * 0.6, v: 0.6), precisa: true);
      expect(r.estado, EstadoDeMovimiento.rodando, reason: 'cortó a los $s s');
    }
  });

  test('semáforo de 90 s no corta el tramo con quietoMin 5', () {
    final d = _rodando();
    final tramo = d.tramo;
    var m = 16.0;
    for (var s = 3; s <= 60; s += 3) {
      m += 12;
      d.lectura(_l(s, m, v: 8), precisa: true);
    }
    for (var s = 63; s <= 150; s += 3) {
      final r = d.lectura(_l(s, m + (s % 3), v: 0.1, acc: 8), precisa: true);
      expect(r.estado, EstadoDeMovimiento.rodando);
    }
    for (var s = 153; s <= 200; s += 3) {
      m += 12;
      expect(d.lectura(_l(s, m, v: 8), precisa: true).estado, EstadoDeMovimiento.rodando);
    }
    expect(d.tramo, tramo);
  });

  test('el tic de 5 s también lo detecta si dejaron de llegar lecturas pero la ventana ya cubre', () {
    final d = _rodando();
    for (var s = 3; s <= 290; s += 3) {
      d.lectura(_l(s, 16 + (s % 3), v: 0.3), precisa: true);
    }
    expect(d.estado, EstadoDeMovimiento.rodando);
    final r = d.tic(1000000 + 330 * 1000);
    expect(r.estado, EstadoDeMovimiento.quieto);
  });
}
