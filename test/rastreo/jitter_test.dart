import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/src/rastreo/emisor_de_lotes.dart';

/// LA DISPERSIÓN DE LOS REINTENTOS TRAS UNA CAÍDA (contrato §4.12).
///
/// 10.000 aparatos mandan su lote en el mismo segundo en que la ingesta se cae. La ingesta
/// sigue caída [caida] y después vuelve. Cada aparato reintenta con su espera; se cuenta
/// cuántos reintentos llegan en cada segundo. Se compara la espera vieja (tope ± 20 %) con
/// el jitter completo (azar entre 0 y el tope). Las cifras se imprimen con el prefijo
/// `JITTER` para copiarlas al resumen; a 1 M de aparatos son ×100.

/// La espera vieja, sólo para comparar: el tope con ±20 %.
Duration _masMenos20(int fallos, math.Random azar) {
  final tope = topeTrasFallo(fallos).inMilliseconds;
  return Duration(milliseconds: (tope * (0.8 + azar.nextDouble() * 0.4)).round());
}

class _Resultado {
  _Resultado(this.porSegundo, this.intentos, this.entregas);
  final Map<int, int> porSegundo;
  final int intentos;

  /// El segundo en que cada aparato entregó (ya con la ingesta arriba), ordenado.
  final List<int> entregas;

  /// Cuántos segundos después de la vuelta de la ingesta entregó el 99 % de los aparatos.
  int p99TrasVolver(int vuelta) => entregas[(entregas.length * 0.99).floor() - 1] - vuelta;

  int get maximo => porSegundo.values.fold(0, math.max);
  int get segundoDelMaximo =>
      porSegundo.entries.reduce((a, b) => b.value > a.value ? b : a).key;

  /// El máximo dentro de una ventana [desde, hasta).
  int maximoEntre(int desde, int hasta) => porSegundo.entries
      .where((e) => e.key >= desde && e.key < hasta)
      .fold(0, (m, e) => math.max(m, e.value));
}

_Resultado _simular({
  required int aparatos,
  required Duration caida,
  required Duration Function(int fallos, math.Random azar) espera,
  required int semilla,
}) {
  final azar = math.Random(semilla);
  final porSegundo = <int, int>{};
  final entregas = <int>[];
  var intentos = 0;
  final finCaida = caida.inMilliseconds;
  for (var a = 0; a < aparatos; a++) {
    var t = 0; // ms: el primer envío falla en el instante de la caída
    var fallos = 1;
    while (true) {
      t += espera(fallos, azar).inMilliseconds;
      intentos++;
      porSegundo.update(t ~/ 1000, (n) => n + 1, ifAbsent: () => 1);
      if (t >= finCaida) {
        entregas.add(t ~/ 1000); // la ingesta ya volvió: aceptado
        break;
      }
      fallos++;
    }
  }
  return _Resultado(porSegundo, intentos, entregas..sort());
}

void main() {
  const aparatos = 10000;

  for (final caida in [const Duration(minutes: 1), const Duration(minutes: 10)]) {
    test('10.000 aparatos tras una caída de ${caida.inMinutes} min: '
        'el jitter completo aplana el pico', () {
      final viejo = _simular(
          aparatos: aparatos, caida: caida, espera: _masMenos20, semilla: 1);
      final nuevo = _simular(
          aparatos: aparatos,
          caida: caida,
          espera: (f, r) => esperaTrasFallo(f, azar: r),
          semilla: 1);
      // El primer reintento: ±20 % los junta entre 24 y 36 s; jitter completo, entre 0 y 30.
      final viejoPrimero = viejo.maximoEntre(0, 40);
      final nuevoPrimero = nuevo.maximoEntre(0, 40);
      // Al volver la ingesta: el pico en el minuto que sigue a la vuelta.
      final s = caida.inSeconds;
      final viejoVuelta = viejo.maximoEntre(s, s + 3600);
      final nuevoVuelta = nuevo.maximoEntre(s, s + 3600);
      // ignore: avoid_print
      print('JITTER caida=${caida.inMinutes}min aparatos=$aparatos '
          '| ±20%: max=${viejo.maximo}/s (seg ${viejo.segundoDelMaximo}), '
          'primer-reintento=$viejoPrimero/s, tras-volver=$viejoVuelta/s, intentos=${viejo.intentos}, '
          'p99-entrega=${viejo.p99TrasVolver(s)}s '
          '| completo: max=${nuevo.maximo}/s (seg ${nuevo.segundoDelMaximo}), '
          'primer-reintento=$nuevoPrimero/s, tras-volver=$nuevoVuelta/s, intentos=${nuevo.intentos}, '
          'p99-entrega=${nuevo.p99TrasVolver(s)}s '
          '| a 1M: ±20% ${viejo.maximo * 100}/s vs completo ${nuevo.maximo * 100}/s');

      // Jitter completo: el pico baja (medido: ~40 %, NO 2,5× — la segunda ronda, que cae
      // entre 0 y 60 s después de la primera, se superpone con ella). Ver RESUMEN-A2.
      expect(nuevo.maximo, lessThan(viejo.maximo * 0.75), reason: 'pico no se aplanó');
      expect(nuevoVuelta, lessThan(viejoVuelta), reason: 'la vuelta no se aplanó');
      // Con ±20 %, en el primer reintento no llega NADIE antes de los 24 s; con jitter
      // completo llegan ~1/30 por segundo desde el segundo 0.
      expect(viejo.maximoEntre(0, 24), 0);
      expect(nuevo.maximoEntre(0, 24), greaterThan(0));
      // No es gratis: se reintenta un poco más (el azar cae a veces cerca de 0).
      expect(nuevo.intentos, lessThan(viejo.intentos * 2));
    });
  }
}
