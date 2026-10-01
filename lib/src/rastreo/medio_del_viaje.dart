import 'detector_de_movimiento.dart';

/// Cuánto dura el medio que la persona declaró (`Rastreo.declararMedio`).
///
/// Declarar arranca un viaje nuevo. El medio se olvida sólo cuando, DESPUÉS de declararlo, el
/// aparato rodó de verdad y luego quedó quieto. «Rodó de verdad» es entrar a rodando después de
/// declarar, o un punto en rodando a la velocidad de arranque o más. El estado heredado de un
/// viaje anterior no cuenta: un detector que quedó en rodando sin lecturas (el viaje anterior
/// terminó y el GPS dejó de entregar) pasa a quieto unos segundos después, y esa quietud no es
/// el fin del viaje declarado (medido el 2026-10-01: 16 de 16 puntos con `medio: null`).
class MedioDelViaje {
  String? _declarado;
  bool _rodo = false;
  EstadoDeMovimiento _ultimo = EstadoDeMovimiento.quieto;
  String? _delViajeTerminado;
  int? _finDelViajeTerminado;

  /// El medio del viaje en curso, o `null` (manda el del perfil).
  String? get declarado => _declarado;

  /// Declara (o con `null`, borra) el medio. [estado] es el que tiene la captura ahora: si ya
  /// estaba rodando, eso no cuenta como haber rodado después de declarar.
  void declarar(String? medio, EstadoDeMovimiento estado) {
    _declarado = medio;
    _rodo = false;
    _ultimo = estado;
    _delViajeTerminado = null;
    _finDelViajeTerminado = null;
  }

  /// Un punto grabado: en rodando y a [arranqueMs] o más, el aparato está rodando de verdad.
  void punto(EstadoDeMovimiento estado, double v, double arranqueMs) {
    if (_declarado != null && estado == EstadoDeMovimiento.rodando && v >= arranqueMs) _rodo = true;
  }

  /// Un cambio de estado de la captura (o de fila, con el mismo estado). Devuelve `true` si el
  /// viaje declarado terminó ahora: el medio se olvida, pero los lotes que se armen con puntos
  /// de hasta [t] lo siguen llevando (ver [paraLote]).
  bool cambio(EstadoDeMovimiento estado, int t) {
    final antes = _ultimo;
    _ultimo = estado;
    if (_declarado == null) return false;
    if (estado == EstadoDeMovimiento.rodando && antes != EstadoDeMovimiento.rodando) _rodo = true;
    if (estado != EstadoDeMovimiento.quieto || !_rodo) return false;
    _delViajeTerminado = _declarado;
    _finDelViajeTerminado = t;
    _declarado = null;
    _rodo = false;
    return true;
  }

  /// El medio que lleva un lote cuyo punto más viejo es de [tMasViejo]: el declarado, o el del
  /// viaje que acaba de terminar si el lote trae puntos suyos (el último lote del viaje puede
  /// armarse después de la quietud: el emisor estaba ocupado o esperando).
  String? paraLote(int? tMasViejo) {
    if (_declarado != null) return _declarado;
    final fin = _finDelViajeTerminado;
    if (fin != null && tMasViejo != null && tMasViejo <= fin) return _delViajeTerminado;
    return null;
  }
}
