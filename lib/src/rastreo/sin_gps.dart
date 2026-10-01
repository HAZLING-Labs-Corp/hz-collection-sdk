/// POR QUÉ NO HAY GPS — el motivo de un `sinGPS` o de un hueco, en el estado LOCAL.
///
/// Tres causas que desde el servidor se ven iguales (no llegan puntos) y que se arreglan
/// distinto: un permiso revocado lo arregla la persona en Ajustes; un GPS apagado, con un
/// toque; un «sin fix» (túnel, sótano, cielo tapado) no lo arregla nadie.
///
/// 🔴 Hoy vive SÓLO en el aparato (diagnóstico): el contrato del lote (`LoteFirmado`, PM-025
/// §4.1) no tiene un campo para el motivo, y agregarlo al cuerpo firmado sin que la ingesta
/// lo conozca es mandar bytes que nadie lee. Queda anotado como pendiente del contrato.
library;

import 'cola_de_rastreo.dart' show Hueco;

enum MotivoSinGps { permisoRevocado, gpsApagado, sinFix }

/// Pura. Devuelve el motivo vigente, o `null` si el GPS está dando puntos (o no se espera
/// que los dé: quieto, el GPS preciso está apagado a propósito).
MotivoSinGps? clasificarSinGps({
  required bool permisoConcedido,
  required bool gpsPrendido,
  required bool moviendose,
  required int? msDesdeElUltimoPunto,
  Duration sinFixTras = const Duration(seconds: 60),
}) {
  if (!permisoConcedido) return MotivoSinGps.permisoRevocado;
  if (!gpsPrendido) return MotivoSinGps.gpsApagado;
  if (moviendose && (msDesdeElUltimoPunto == null || msDesdeElUltimoPunto > sinFixTras.inMilliseconds)) {
    return MotivoSinGps.sinFix;
  }
  return null;
}

/// Un rato sin GPS con su motivo. `hasta == null`: sigue.
class TramoSinGps {
  TramoSinGps(this.motivo, this.desde, [this.hasta]);
  final MotivoSinGps motivo;
  final int desde;
  int? hasta;
}

/// El registro de los ratos sin GPS (los últimos [maximo]), y el motivo de un hueco: el del
/// rato que más se le cruza; si ninguno, `sinFix` (el permiso y el GPS estaban bien y el
/// sistema igual no dio posición).
class RegistroSinGps {
  RegistroSinGps({this.maximo = 50});
  final int maximo;
  final List<TramoSinGps> tramos = [];

  MotivoSinGps? get vigente => tramos.isNotEmpty && tramos.last.hasta == null ? tramos.last.motivo : null;

  /// Aplica el motivo de ahora: abre, cierra o cambia el rato vigente.
  void anotar(MotivoSinGps? motivo, int ahora) {
    if (motivo == vigente) return;
    if (tramos.isNotEmpty && tramos.last.hasta == null) tramos.last.hasta = ahora;
    if (motivo != null) tramos.add(TramoSinGps(motivo, ahora));
    while (tramos.length > maximo) {
      tramos.removeAt(0);
    }
  }

  MotivoSinGps motivoDe(Hueco h, {int? ahora}) {
    MotivoSinGps? mejor;
    var cruce = 0;
    for (final t in tramos) {
      final fin = t.hasta ?? ahora ?? h.hasta;
      final c = (fin < h.hasta ? fin : h.hasta) - (t.desde > h.desde ? t.desde : h.desde);
      if (c > cruce) {
        cruce = c;
        mejor = t.motivo;
      }
    }
    return mejor ?? MotivoSinGps.sinFix;
  }
}
