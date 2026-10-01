/// EL PULSO SIN FCM — el servidor pide una posición precisa en la respuesta de la presencia.
///
/// La respuesta 202 de `POST /presencia` (y de `/latidos`) puede traer
/// `pulso: {id: string, hasta: number}` (ms epoch). Si el SDK lo ve y no ha vencido:
///
///  1. toma UNA posición precisa (timeout 20 s),
///  2. manda `POST /presencia` con `origen: 'pulso'` y `pulsoId`.
///
/// Idempotente: el mismo id se atiende una sola vez (aunque la posición falle: el servidor
/// pedirá otro pulso con otro id). Si el servidor apagó la captura, no responde.
///
/// Pieza aparte de `Rastreo` para probarla sin teléfono: todo se inyecta.
library;

import 'dart:async';
import 'dart:convert';

import 'api_de_rastreo.dart';

/// El pulso que pidió el servidor.
class PulsoPedido {
  const PulsoPedido(this.id, this.hasta);
  final String id;
  final int hasta;

  /// Lee `pulso` del cuerpo de una respuesta 2xx. `null` si no vino o viene mal formado.
  static PulsoPedido? deRespuesta(RespuestaDeIngesta r) {
    final texto = r.cuerpoCompleto ?? r.cuerpo;
    if (!r.aceptado || texto == null) return null;
    try {
      final j = jsonDecode(texto);
      final p = j is Map ? j['pulso'] : null;
      if (p is! Map) return null;
      final id = p['id'];
      final hasta = p['hasta'];
      if (id is! String || id.isEmpty || hasta is! num) return null;
      return PulsoPedido(id, hasta.toInt());
    } catch (_) {
      return null;
    }
  }
}

class PulsoPorPresencia {
  PulsoPorPresencia({
    required this.tomarPosicion,
    required this.enviarPresencia,
    required this.apagado,
    int Function()? ahora,
    this.timeout = const Duration(seconds: 20),
  }) : _ahora = ahora ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Una posición precisa, con los campos de la presencia (`t`, `lat`, `lon`, `acc`, `v`, `h`,
  /// `estado`, `bat`, `instalacionId`…) SIN `origen` ni `pulsoId`. `null` si no hay fix.
  final Future<Map<String, dynamic>?> Function() tomarPosicion;
  final Future<RespuestaDeIngesta> Function(Map<String, dynamic> cuerpo) enviarPresencia;

  /// ¿El servidor apagó la captura? Entonces no se responde.
  final bool Function() apagado;
  final int Function() _ahora;
  final Duration timeout;

  final _vistos = <String>[];
  int respondidos = 0;
  String? ultimoProblema;

  /// Mira una respuesta de la ingesta. Devuelve `true` si atendió un pulso (mandó la presencia).
  Future<bool> alResponder(RespuestaDeIngesta r) async {
    final p = PulsoPedido.deRespuesta(r);
    if (p == null) return false;
    return atender(p);
  }

  Future<bool> atender(PulsoPedido p) async {
    if (apagado()) return false;
    if (p.hasta <= _ahora()) return false; // vencido
    if (_vistos.contains(p.id)) return false; // ya atendido (o en curso)
    _vistos.add(p.id);
    if (_vistos.length > 64) _vistos.removeAt(0);
    try {
      final base = await tomarPosicion().timeout(timeout);
      if (base == null) {
        ultimoProblema = 'pulso sin posición';
        return false;
      }
      if (apagado()) return false; // se apagó mientras se esperaba el fix
      final r = await enviarPresencia({...base, 'origen': 'pulso', 'pulsoId': p.id});
      if (!r.aceptado) {
        ultimoProblema = 'pulso: ${r.codigo ?? 'sin red'}';
        return false;
      }
      respondidos++;
      return true;
    } catch (e) {
      ultimoProblema = 'pulso sin posición: $e';
      return false;
    }
  }
}
