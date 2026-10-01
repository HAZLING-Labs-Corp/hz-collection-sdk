/// EL VIGÍA DEL GOLPE — enchufa el acelerómetro al [DetectorDeGolpe].
///
/// Escucha a 50 Hz (`SensorInterval.gameInterval`) SÓLO mientras la captura no está quieta
/// —un choque pasa andando— o mientras el detector está midiendo una quietud. Quieto y sin
/// golpe en curso, el sensor se suelta: 50 Hz todo el día es batería que no se justifica.
/// (El despertar por acelerómetro de la captura propia es otra suscripción, a 5 Hz, y sólo en
/// quieto: no se pisan.)
///
/// Un pico de un choque dura 10-50 ms; a los 5 Hz del despertar se escaparía casi siempre.
library;

import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import 'detector_de_golpe.dart';

class VigiaDeGolpe {
  VigiaDeGolpe({required this.detector, required this.alGolpe, this.alProblema});

  final DetectorDeGolpe detector;
  final void Function(GolpeDetectado g) alGolpe;
  final void Function(String p)? alProblema;

  StreamSubscription<AccelerometerEvent>? _sub;
  bool _quiereEscuchar = false;

  bool get escuchando => _sub != null;

  /// Lo llama el rastreo en cada cambio de estado: `true` mientras la persona se mueve.
  void moviendose(bool si) {
    _quiereEscuchar = si;
    _ajustar();
  }

  void _ajustar() {
    final hace = _quiereEscuchar || detector.ocupado;
    if (hace && _sub == null) {
      try {
        _sub = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
          (e) => _muestra(MuestraDeAceleracion(t: DateTime.now().millisecondsSinceEpoch, x: e.x, y: e.y, z: e.z)),
          onError: (Object e) => alProblema?.call('acelerómetro del golpe: $e'),
        );
      } catch (e) {
        alProblema?.call('acelerómetro del golpe: $e');
      }
    } else if (!hace && _sub != null) {
      unawaited(_sub!.cancel());
      _sub = null;
    }
  }

  void _muestra(MuestraDeAceleracion m) {
    final g = detector.muestra(m);
    if (g != null) alGolpe(g);
    if (!_quiereEscuchar && !detector.ocupado) _ajustar();
  }

  Future<void> detener() async {
    _quiereEscuchar = false;
    await _sub?.cancel();
    _sub = null;
  }
}
