import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/src/rastreo/cadencia.dart';
import 'package:hz_collection_sdk/src/rastreo/configuracion_de_rastreo.dart';

/// La tabla de PM-025 §4.5 («Cambio del 30-09-2026»), copiada campo por campo.
const tablaDelContrato = [
  {'estado': 'emergencia', 'si': {'forzado': true}, 'muestreoSeg': 2, 'presenciaSeg': 5, 'loteSeg': 15},
  {'estado': 'rapido', 'si': {'velKmhMayorA': 40}, 'muestreoSeg': 5, 'presenciaSeg': 15, 'loteSeg': 120},
  {'estado': 'rodando', 'si': {'enMovimiento': true}, 'muestreoSeg': 10, 'presenciaSeg': 20, 'loteSeg': 300},
  {
    'estado': 'nocheQuieto',
    'si': {'quietoMinMayorA': 30, 'horaEntre': ['22:00', '06:00']},
    'muestreoSeg': 0, 'presenciaSeg': 0, 'latidoMin': 180
  },
  {'estado': 'detenido', 'si': {'quietoMinMayorA': 5}, 'muestreoSeg': 0, 'presenciaSeg': 0, 'latidoMin': 30},
];

void main() {
  final config = ConfiguracionDeRastreo.fromJson({
    'activo': true,
    'perfil': 'persona-en-movimiento',
    'arranqueKmh': 10,
    'quietoMin': 5,
    'golpe': {'g': 4, 'quietoSeg': 60},
    'estadoForzado': null,
    'cadencia': tablaDelContrato,
  });
  final tabla = config.cadencia;

  SituacionDelAparato s({
    bool forzado = false,
    double vel = 0,
    bool mov = false,
    double quieto = 0,
    int hora = 12,
    int minuto = 0,
  }) =>
      SituacionDelAparato(
          forzado: forzado, velKmh: vel, enMovimiento: mov, quietoMin: quieto,
          hora: DateTime(2026, 9, 30, hora, minuto));

  String fila(SituacionDelAparato x) => evaluarCadencia(tabla, x).estado;

  test('se leen las cinco filas con sus números', () {
    expect(tabla.map((f) => f.estado).toList(),
        ['emergencia', 'rapido', 'rodando', 'nocheQuieto', 'detenido']);
    expect(tabla[1].muestreoSeg, 5);
    expect(tabla[1].loteSeg, 120);
    expect(tabla[3].latidoMin, 180);
    expect(tabla[3].loteSeg, isNull);
    expect(tabla[4].muestreoSeg, 0);
  });

  test('las cinco filas, cada una con su situación', () {
    expect(fila(s(forzado: true, vel: 60, mov: true)), 'emergencia');
    expect(fila(s(vel: 60, mov: true)), 'rapido');
    expect(fila(s(vel: 25, mov: true)), 'rodando');
    expect(fila(s(quieto: 45, hora: 23)), 'nocheQuieto');
    expect(fila(s(quieto: 10, hora: 15)), 'detenido');
  });

  test('borde: 40 km/h justos no es rápido; 40,1 sí', () {
    expect(fila(s(vel: 40, mov: true)), 'rodando');
    expect(fila(s(vel: 40.1, mov: true)), 'rapido');
  });

  test('borde: 22:00 justo ya es noche; 21:59 no; 06:00 ya no', () {
    expect(fila(s(quieto: 45, hora: 22, minuto: 0)), 'nocheQuieto');
    expect(fila(s(quieto: 45, hora: 21, minuto: 59)), 'detenido');
    expect(fila(s(quieto: 45, hora: 5, minuto: 59)), 'nocheQuieto');
    expect(fila(s(quieto: 45, hora: 6, minuto: 0)), 'detenido');
    expect(fila(s(quieto: 45, hora: 0, minuto: 30)), 'nocheQuieto', reason: 'cruza medianoche');
  });

  test('borde: quieto 5 min justos todavía no es detenido; 30 justos de noche no es noche', () {
    expect(fila(s(quieto: 5)), 'quieto', reason: 'ninguna fila y no rueda → quieto sin GPS');
    expect(fila(s(quieto: 5.01)), 'detenido');
    expect(fila(s(quieto: 30, hora: 23)), 'detenido');
    expect(fila(s(quieto: 30.5, hora: 23)), 'nocheQuieto');
  });

  test('sin tabla, o tabla vacía: el respaldo rodando 10/20/300', () {
    final vacia = ConfiguracionDeRastreo.fromJson({'activo': true});
    final f = vacia.filaPara(s(vel: 90, mov: true));
    expect(f.estado, 'rodando');
    expect((f.muestreoSeg, f.presenciaSeg, f.loteSeg), (10, 20, 300));
    expect(vacia.muestreoDelGpsSeg, 10);
  });

  test('una condición desconocida hace que la fila no se cumpla nunca', () {
    final t = ConfiguracionDeRastreo.fromJson({
      'cadencia': [
        {'estado': 'nuevo', 'si': {'bateriaMenorA': 20}, 'muestreoSeg': 1, 'loteSeg': 10},
        {'estado': 'rodando', 'si': {'enMovimiento': true}, 'muestreoSeg': 10, 'loteSeg': 300},
      ]
    }).cadencia;
    expect(evaluarCadencia(t, s(mov: true)).estado, 'rodando');
  });

  test('los pisos: nadie pide un lote cada segundo', () {
    final f = FilaDeCadencia.fromJson({'estado': 'x', 'muestreoSeg': 0.6, 'loteSeg': 0});
    expect(f.muestreoSeg, 1);
    expect(f.loteSeg, FilaDeCadencia.pisoLoteSeg);
    expect(FilaDeCadencia.fromJson({'estado': 'q', 'muestreoSeg': 0}).muestreoSeg, 0, reason: 'cero = GPS apagado');
  });

  test('el GPS se abre al muestreo más corto que puede tocar (sin la de emergencia si nadie la forzó)', () {
    expect(config.muestreoDelGpsSeg, 5);
    final forzada = ConfiguracionDeRastreo.fromJson(
        {'estadoForzado': 'emergencia', 'cadencia': tablaDelContrato});
    expect(forzada.muestreoDelGpsSeg, 2);
  });
}
