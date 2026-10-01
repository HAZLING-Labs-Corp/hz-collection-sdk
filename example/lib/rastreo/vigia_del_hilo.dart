/// EL VIGÍA DEL HILO PRINCIPAL — mide si algo lo tuvo tomado, venga de Dart o del nativo.
///
/// Un reloj de Dart que debería sonar cada [cada]. Con los hilos fusionados (Flutter 3.29+)
/// el isolate de Dart y el hilo principal de Android son el mismo: si el reloj suena tarde,
/// ALGO tuvo el hilo tomado ese tiempo —trabajo de Dart de corrido, o un `MethodChannel`
/// haciendo algo lento en el principal—. Es la misma cuenta que hace Android para el ANR
/// (5 s sin atender un toque), medida desde adentro.
///
/// Cada [informe] imprime una línea `HzRastreoHilo vigia` con el peor atraso y cuántos
/// pasaron de 16 ms (un cuadro), 100 ms, 700 ms y 5 s. Sólo en la app de diagnóstico.
library;

import 'dart:async';

class VigiaDelHilo {
  VigiaDelHilo({
    this.cada = const Duration(milliseconds: 50),
    this.informe = const Duration(seconds: 30),
  });

  final Duration cada;
  final Duration informe;

  Timer? _tic;
  Timer? _reporte;
  final _reloj = Stopwatch();
  int _anterior = 0;
  double _peorMs = 0;
  double _peorTotalMs = 0;
  final _cuenta = {16: 0, 100: 0, 700: 0, 5000: 0};
  int _tics = 0;

  void arrancar() {
    _reloj.start();
    _anterior = _reloj.elapsedMicroseconds;
    _tic = Timer.periodic(cada, (_) {
      final ahora = _reloj.elapsedMicroseconds;
      final atraso = (ahora - _anterior) / 1000 - cada.inMilliseconds;
      _anterior = ahora;
      _tics++;
      if (atraso > _peorMs) _peorMs = atraso;
      if (atraso > _peorTotalMs) _peorTotalMs = atraso;
      for (final u in _cuenta.keys) {
        if (atraso > u) _cuenta[u] = _cuenta[u]! + 1;
      }
    });
    _reporte = Timer.periodic(informe, (_) {
      // ignore: avoid_print
      print('HzRastreoHilo vigia ventana=${informe.inSeconds}s tics=$_tics '
          'peor=${_peorMs.toStringAsFixed(1)}ms peorDesdeArranque=${_peorTotalMs.toStringAsFixed(1)}ms '
          '>16ms=${_cuenta[16]} >100ms=${_cuenta[100]} >700ms=${_cuenta[700]} >5s=${_cuenta[5000]}');
      _peorMs = 0;
      _tics = 0;
      for (final u in _cuenta.keys) {
        _cuenta[u] = 0;
      }
    });
  }

  void parar() {
    _tic?.cancel();
    _reporte?.cancel();
  }
}
