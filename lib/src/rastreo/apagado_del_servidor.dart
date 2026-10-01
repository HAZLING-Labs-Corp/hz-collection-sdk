/// EL SERVIDOR APAGÓ EL RASTREO — qué hace el SDK con un `403 rastreo_apagado` (el interruptor
/// del comercio) o `403 medicion_apagada` (la medición de la persona, tramo 4.2 del back).
///
///  1. **Deja de capturar y de enviar**: la captura se detiene y el emisor no vuelve a mandar
///     lotes (ni la presencia) mientras dure.
///  2. **No reintenta en bucle esos lotes**: no son lotes malos — el servidor no quiere nada ahora.
///     Quedan guardados en la cola tal cual (firmados, encadenados) y NO se marcan rechazados.
///  3. **Vuelve a leer la configuración con espera creciente** (1, 2, 4… min, techo 1 h, con
///     jitter completo: un comercio que apaga a todos no recibe a todos de vuelta en el mismo
///     segundo). Cuando la configuración vuelve con `activo: true`, se retoma la captura y se
///     manda la cola.
///
/// Es una pieza aparte de `Rastreo` para poder probarla sin teléfono: el reloj y el «releer» se
/// inyectan.
library;

import 'dart:async';
import 'dart:math' as math;

/// Los dos motivos por los que la ingesta dice «no quiero nada ahora».
const codigosDeApagado = {'rastreo_apagado', 'medicion_apagada'};

/// ¿Esta respuesta es «el servidor apagó el rastreo»? 403 con uno de los dos códigos.
bool esApagadoDelServidor(int? codigo, String? errorDelCuerpo) =>
    codigo == 403 && errorDelCuerpo != null && codigosDeApagado.contains(errorDelCuerpo);

/// El TOPE de la espera antes de la relectura número [intento] (1 = la primera): 1, 2, 4… min,
/// con techo de 1 h. Es el techo del azar, no la espera.
Duration topeDeRelectura(int intento) {
  const base = 60; // segundos
  const techo = 3600;
  final exp = intento <= 1 ? 0 : (intento - 1).clamp(0, 16);
  return Duration(seconds: math.min(techo, base * math.pow(2, exp).toInt()));
}

/// La espera, con JITTER COMPLETO entre la mitad del tope y el tope: nunca 0 (no se martilla
/// `/configuracion` apenas apagaron) y repartida (no vuelven todos juntos).
Duration esperaDeRelectura(int intento, math.Random azar) {
  final tope = topeDeRelectura(intento).inMilliseconds;
  return Duration(milliseconds: (tope / 2 + azar.nextDouble() * tope / 2).round());
}

typedef Programar = void Function() Function(Duration espera, void Function() cuando);

/// Lo que hace `Timer` por omisión; en las pruebas se inyecta un reloj de mentira.
void Function() programarConTimer(Duration espera, void Function() cuando) {
  final t = Timer(espera, cuando);
  return t.cancel;
}

class VigiaDelApagado {
  VigiaDelApagado({
    required this.releerActivo,
    required this.alVolver,
    Programar? programar,
    math.Random? azar,
  })  : _programar = programar ?? programarConTimer,
        _azar = azar ?? math.Random();

  /// Relee `/configuracion` y dice si volvió `activo: true` (`null` si no se pudo leer).
  final Future<bool?> Function() releerActivo;

  /// Se llama UNA vez cuando la configuración vuelve encendida: retomar la captura y mandar la cola.
  final Future<void> Function() alVolver;

  final Programar _programar;
  final math.Random _azar;

  bool _apagado = false;
  String? _motivo;
  int _intentos = 0;
  void Function()? _cancelar;
  DateTime? _proximaRelectura;

  bool get apagado => _apagado;

  /// `rastreo_apagado` o `medicion_apagada`.
  String? get motivo => _motivo;
  int get relecturas => _intentos;
  DateTime? get proximaRelectura => _proximaRelectura;

  /// El servidor dijo que no. Idempotente: un segundo 403 no reinicia la espera.
  void apagar(String motivo) {
    _motivo = motivo;
    if (_apagado) return;
    _apagado = true;
    _intentos = 0;
    _siguiente();
  }

  void _siguiente() {
    _cancelar?.call();
    _intentos++;
    final espera = esperaDeRelectura(_intentos, _azar);
    _proximaRelectura = DateTime.now().add(espera);
    _cancelar = _programar(espera, () => unawaited(_releer()));
  }

  Future<void> _releer() async {
    if (!_apagado) return;
    bool? activo;
    try {
      activo = await releerActivo();
    } catch (_) {
      activo = null;
    }
    if (!_apagado) return;
    if (activo == true) {
      await encender();
      return;
    }
    _siguiente();
  }

  /// La configuración volvió encendida (por esta relectura o por la de cada hora).
  Future<void> encender() async {
    if (!_apagado) return;
    _apagado = false;
    _cancelar?.call();
    _cancelar = null;
    _proximaRelectura = null;
    _intentos = 0;
    await alVolver();
  }

  void detener() {
    _cancelar?.call();
    _cancelar = null;
  }
}
