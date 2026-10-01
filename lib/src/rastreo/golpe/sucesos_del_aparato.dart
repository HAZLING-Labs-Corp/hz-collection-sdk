/// LOS SUCESOS URGENTES DEL APARATO — `POST /api/v1/rastreo/sucesos` (PM-025 §4.4).
///
/// ```
/// { instalacionId, id, tipo: golpe_quietud|quieto|sin_gps, t, confianza: 0..1, puntos?: [≤10] }
/// ```
///
/// ══ 🔴 SALE EN EL ACTO, NO CON EL LOTE ══
///
/// Un golpe no espera los cinco minutos del lote. Se manda apenas el detector lo concluye;
/// si no hay red, queda en una cola persistente (sobrevive a que maten la app) y se reintenta
/// con espera creciente y jitter completo, la misma de los lotes.
///
/// ══ REINTENTAR ES IDEMPOTENTE ══
///
/// El `id` es el SHA-256 hex de `instalacionId|tipo|t`: el mismo suceso tiene siempre el
/// mismo id, y la ingesta contesta 200 si ya lo tenía. Por eso un 200 es «entregado», igual
/// que el 202. Un 202 `{ignorado: true}` (el comercio apagó ese tipo) también se da por
/// entregado: reintentar daría lo mismo.
///
/// | respuesta | qué pasa |
/// |---|---|
/// | 200 / 202 | entregado: sale de la cola |
/// | 429 / 503 | se reintenta tras `Retry-After` (techo 1 h) + azar |
/// | sin red, 408, 5xx | espera creciente con jitter completo (30 s, 1, 2… techo 30 min) |
/// | 400 / otro 4xx | descartado: los mismos bytes darían lo mismo. Queda en el diagnóstico |
library;

import 'dart:convert';
import 'dart:math' as math;

import '../api_de_rastreo.dart';
import '../canonico.dart';
import '../emisor_de_lotes.dart' show esperaTrasFallo, esperaTrasRetryAfter;
import '../punto.dart';

/// Los tipos que manda el aparato.
abstract final class TipoDeSuceso {
  static const golpeQuietud = 'golpe_quietud';
  static const quieto = 'quieto';
  static const sinGps = 'sin_gps';
  static const todos = {golpeQuietud, quieto, sinGps};
}

/// El id determinista: SHA-256 hex de `instalacionId|tipo|t`.
String idDelSuceso(String instalacionId, String tipo, int t) => sha256Hex('$instalacionId|$tipo|$t');

/// Un suceso del aparato, tal como sale y como lo ve la app.
class SucesoDelAparato {
  SucesoDelAparato({
    required this.instalacionId,
    required this.tipo,
    required this.t,
    required double confianza,
    List<PuntoDeRastreo> puntos = const [],
    this.simulado = false,
  })  : id = idDelSuceso(instalacionId, tipo, t),
        confianza = (confianza.clamp(0.0, 1.0) * 100).round() / 100,
        puntos = List.unmodifiable(puntos.length > maximoDePuntos ? puntos.sublist(puntos.length - maximoDePuntos) : puntos);

  /// El contrato acepta hasta 10.
  static const maximoDePuntos = 10;

  final String instalacionId;
  final String id;
  final String tipo;

  /// La hora del suceso (para un golpe, la del pico), ms desde época.
  final int t;
  final double confianza;

  /// Los últimos puntos antes del suceso (hasta 10).
  final List<PuntoDeRastreo> puntos;

  /// Si salió de `Rastreo.simularGolpe`. NO viaja: el contrato no lo tiene. Es para la app.
  final bool simulado;

  Map<String, dynamic> toJson() => {
        'instalacionId': instalacionId,
        'id': id,
        'tipo': tipo,
        't': t,
        'confianza': confianza,
        if (puntos.isNotEmpty) 'puntos': [for (final p in puntos) p.toJson()],
      };

  Map<String, dynamic> _paraGuardar() => {...toJson(), 'simulado': simulado};

  static SucesoDelAparato? _deGuardado(Object? j) {
    if (j is! Map) return null;
    try {
      return SucesoDelAparato(
        instalacionId: j['instalacionId'] as String,
        tipo: j['tipo'] as String,
        t: (j['t'] as num).toInt(),
        confianza: (j['confianza'] as num).toDouble(),
        puntos: [
          for (final p in (j['puntos'] as List?) ?? const [])
            PuntoDeRastreo.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
        simulado: j['simulado'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => '$tipo · ${DateTime.fromMillisecondsSinceEpoch(t).toIso8601String()} · confianza $confianza';
}

/// Lo que pasó al intentar mandar la cola.
class ResultadoDeSucesos {
  const ResultadoDeSucesos({required this.entregados, required this.descartados, required this.pendientes, this.proximoIntento});
  final int entregados;
  final int descartados;
  final int pendientes;
  final DateTime? proximoIntento;
}

/// La cola de sucesos y quien la manda. La cola es chica (un puñado de sucesos) y vive en
/// la tabla `estado` de la cola del rastreo, como un JSON: no hace falta una tabla nueva.
class EmisorDeSucesos {
  EmisorDeSucesos({
    required this.api,
    required this.leer,
    required this.escribir,
    DateTime Function()? ahora,
    math.Random? azar,
  })  : _ahora = ahora ?? DateTime.now,
        _azar = azar ?? math.Random();

  final ApiDeRastreo api;

  /// Lee y escribe la cola persistente (un JSON). En el SDK, `ColaDeRastreo.leer/escribir`.
  final Future<String?> Function() leer;
  final Future<void> Function(String? valor) escribir;
  final DateTime Function() _ahora;
  final math.Random _azar;

  /// Un suceso viejo no sirve para «¿estás bien?» pero sí para el expediente: se guarda dos días.
  static const vencimiento = Duration(hours: 48);

  /// Techo de la cola: más que esto es un aparato que no tiene red hace días.
  static const techo = 50;

  int _fallos = 0;
  DateTime? _noAntesDe;
  bool _ocupado = false;
  String? ultimoError;

  DateTime? get proximoIntento => _noAntesDe;
  int get fallosSeguidos => _fallos;

  Future<List<SucesoDelAparato>> pendientes() async {
    final crudo = await leer();
    if (crudo == null || crudo.isEmpty) return [];
    try {
      final l = jsonDecode(crudo);
      if (l is! List) return [];
      return l.map(SucesoDelAparato._deGuardado).whereType<SucesoDelAparato>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _guardar(List<SucesoDelAparato> l) =>
      escribir(l.isEmpty ? null : jsonEncode([for (final s in l) s._paraGuardar()]));

  /// Encola el suceso (si no estaba ya) y lo intenta mandar YA: un suceso nuevo salta la
  /// espera creciente — es la razón de ser de esta cola.
  Future<ResultadoDeSucesos> encolarYEnviar(SucesoDelAparato s) async {
    final l = await pendientes();
    if (!l.any((x) => x.id == s.id)) l.add(s);
    while (l.length > techo) {
      l.removeAt(0);
    }
    await _guardar(l);
    _noAntesDe = null;
    return intentar();
  }

  /// Manda lo que haya en la cola, si no está esperando.
  Future<ResultadoDeSucesos> intentar() async {
    if (_ocupado) return ResultadoDeSucesos(entregados: 0, descartados: 0, pendientes: (await pendientes()).length, proximoIntento: _noAntesDe);
    _ocupado = true;
    try {
      final ahora = _ahora();
      var l = await pendientes();
      l = [for (final s in l) if (ahora.millisecondsSinceEpoch - s.t < vencimiento.inMilliseconds) s];
      final n = _noAntesDe;
      if (l.isEmpty || (n != null && ahora.isBefore(n))) {
        await _guardar(l);
        return ResultadoDeSucesos(entregados: 0, descartados: 0, pendientes: l.length, proximoIntento: l.isEmpty ? null : n);
      }
      var entregados = 0, descartados = 0;
      final quedan = <SucesoDelAparato>[];
      Duration? espera;
      for (final s in l) {
        if (espera != null) {
          quedan.add(s);
          continue;
        }
        final r = await api.enviarSuceso(s.toJson());
        final c = r.codigo;
        if (c == 200 || c == 202 || c == 201) {
          entregados++;
        } else if (c == 429 || c == 503) {
          quedan.add(s);
          _fallos++;
          espera = r.reintentarEn != null
              ? esperaTrasRetryAfter(r.reintentarEn!, azar: _azar)
              : esperaTrasFallo(_fallos, azar: _azar);
          ultimoError = '$c ${r.cuerpo ?? ''}';
        } else if (c == null || c == 408 || c >= 500) {
          quedan.add(s);
          _fallos++;
          espera = esperaTrasFallo(_fallos, azar: _azar);
          ultimoError = c == null ? 'sin red: ${r.error ?? ''}' : '$c ${r.cuerpo ?? ''}';
        } else {
          descartados++; // 400 / otro 4xx: lo mismo daría lo mismo
          ultimoError = '$c ${r.cuerpo ?? ''}';
        }
      }
      if (espera == null) _fallos = 0;
      _noAntesDe = espera == null ? null : _ahora().add(espera);
      await _guardar(quedan);
      return ResultadoDeSucesos(entregados: entregados, descartados: descartados, pendientes: quedan.length, proximoIntento: _noAntesDe);
    } finally {
      _ocupado = false;
    }
  }

  /// Volvió la red o la app al frente: se olvida la espera creciente y el próximo
  /// [intentar] sale ya. Son a lo sumo un puñado de sucesos: no hace falta el azar corto
  /// que usan los lotes.
  void reiniciarEspera() {
    _fallos = 0;
    _noAntesDe = null;
  }
}
