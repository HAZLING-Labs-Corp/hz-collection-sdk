/// EL EMISOR — cuándo se arma un lote, cómo se manda, y qué se hace con cada respuesta.
///
/// ══ CUÁNDO SE ARMA ══
///
/// Cuando hay [ConfiguracionDeRastreo.lotePuntos] esperando (el techo global), o cuando el
/// más viejo que espera tiene el `loteSeg` de la fila de cadencia que manda ahora (300 s
/// rodando, 120 s rápido, 15 s forzado) — lo que llegue primero. Y siempre al
/// detenerse la persona (`forzar`), para que el recorrido no quede en el teléfono hasta que
/// vuelva a moverse.
///
/// ══ 🔴 UN LOTE EN VUELO A LA VEZ, Y EN ORDEN ══
///
/// El siguiente no se arma hasta que el anterior tuvo respuesta definitiva: su
/// `hashAnterior` es el hash del último que la ingesta ACEPTÓ. Mandar dos en paralelo
/// haría que el segundo llegara, a veces, antes que el primero, y la cadena se rompería
/// por una carrera de red.
///
/// ══ QUÉ SE HACE CON CADA RESPUESTA ══
///
/// | respuesta | qué pasa |
/// |---|---|
/// | 200 / 202 | aceptado. Se guarda su hash como el anterior del siguiente. Si queda atraso, se sigue |
/// | 429 | se espera lo que diga `Retry-After` (techo 1 h), o la espera creciente si no lo dice |
/// | 5xx, 408, sin red | espera creciente: 30 s, 1, 2, 4… con techo de 30 min y ±20 % de azar |
/// | 409 `en_proceso` | el mismo lote después de `Retry-After` (otra petición lo está escribiendo) |
/// | 409 `cadena_rota` | se DESARMA el lote (sus puntos vuelven a la cola) y se encadena al `ultimoHash` que manda la ingesta |
/// | 401 `clave_desconocida` | se re-registra la clave y se reintenta el MISMO lote; al tercer 401, rechazado |
/// | 401 `hash_no_coincide` / `firma_invalida`, otro 4xx | rechazado: los mismos bytes van a dar lo mismo. Se guarda para el diagnóstico |
///
/// Y un techo propio: a lo sumo 5 lotes por minuto (la ingesta corta en 6).
///
/// 🔴 **El azar de la espera no es un adorno.** Un millón de teléfonos que perdieron la
/// señal a la vez —un corte de la operadora— la recuperan a la vez. Sin azar reintentan
/// todos en el mismo segundo, cada 30 s, 1 min, 2 min… y la ingesta recibe olas de un
/// millón de requests. Con ±20 % las olas se aplanan.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'api_de_rastreo.dart';
import 'cola_de_rastreo.dart';
import 'configuracion_de_rastreo.dart';
import 'lote.dart';

/// Lo que pasó en un intento, para el diagnóstico.
class ResultadoDelEmisor {
  const ResultadoDelEmisor(this.que, {this.loteId, this.codigo, this.proximoIntento});

  /// `nadaQueMandar` · `esperando` · `enviado` · `reintentar` · `rechazado` · `resincronizado`.
  final String que;
  final String? loteId;
  final int? codigo;
  final DateTime? proximoIntento;

  @override
  String toString() => 'ResultadoDelEmisor($que, lote: $loteId, código: $codigo, '
      'próximo: $proximoIntento)';
}

/// La espera tras [fallos] fallos seguidos (1 = el primero). Pura, para poder probarla.
Duration esperaTrasFallo(int fallos, {math.Random? azar}) {
  const base = 30; // segundos
  const techo = 30 * 60;
  final exp = fallos <= 1 ? 0 : (fallos - 1).clamp(0, 16);
  final seg = math.min(techo, base * math.pow(2, exp).toInt());
  final factor = 0.8 + (azar ?? math.Random()).nextDouble() * 0.4; // ±20 %
  return Duration(milliseconds: (seg * 1000 * factor).round());
}

class EmisorDeLotes {
  EmisorDeLotes({
    required this.cola,
    required this.api,
    required this.firmador,
    required this.instalacionId,
    required this.reloj,
    required this.configuracion,
    required this.loteSeg,
    required this.registrarClave,
    DateTime Function()? ahora,
    math.Random? azar,
  })  : _ahora = ahora ?? DateTime.now,
        _azar = azar ?? math.Random();

  final ColaDeRastreo cola;
  final ApiDeRastreo api;
  final FirmadorDeLotes firmador;
  final String instalacionId;
  final Future<RelojDelLote> Function(int? gnss) reloj;
  final ConfiguracionDeRastreo Function() configuracion;

  /// El `loteSeg` de la fila de cadencia vigente (o el del respaldo si la fila no lo dice).
  final int Function() loteSeg;

  /// Vuelve a registrar la pública. Devuelve si la ingesta la aceptó.
  final Future<bool> Function() registrarClave;

  /// Los envíos del último minuto. La ingesta acepta a lo sumo 6 lotes por minuto por
  /// instalación (RESUMEN-B §8); el SDK se queda en [maximoPorMinuto] para no gastar un 429.
  final List<DateTime> _envios = [];
  static const maximoPorMinuto = 5;

  final DateTime Function() _ahora;
  final math.Random _azar;

  /// Techo del `Retry-After` que se obedece. Un servidor que pide un día de espera está
  /// roto, y obedecerlo dejaría el teléfono un día sin mandar.
  static const techoRetryAfter = Duration(hours: 1);

  /// Cuántos 401 seguidos se toleran antes de dar un lote por rechazado.
  static const maximo401 = 3;

  /// Cuántos lotes se mandan seguidos en una sola llamada cuando hay atraso. Más no es
  /// más rápido: es acaparar la red del teléfono en un solo despertar.
  static const maximoPorVuelta = 10;

  int _fallosSeguidos = 0;
  int _rechazosDeFirma = 0;
  DateTime? _noAntesDe;
  bool _ocupado = false;

  DateTime? get proximoIntento => _noAntesDe;
  int get fallosSeguidos => _fallosSeguidos;

  /// Olvida la espera por fallos de red. Se llama cuando vuelve la conectividad: la
  /// espera existía porque no había red, y ya hay. NO olvida un `Retry-After`.
  bool _esperaEsPorRetryAfter = false;
  void volvioLaRed() {
    if (!_esperaEsPorRetryAfter) {
      _noAntesDe = null;
      _fallosSeguidos = 0;
    }
  }

  /// Un intento. [forzar] arma un lote con lo que haya aunque no se haya cumplido ni el
  /// tiempo ni la cantidad (al detenerse, o por el botón del diagnóstico). No salta la
  /// espera: forzar no es martillar.
  Future<ResultadoDelEmisor> intentar({bool forzar = false}) async {
    if (_ocupado) return const ResultadoDelEmisor('esperando');
    _ocupado = true;
    try {
      ResultadoDelEmisor ultimo = const ResultadoDelEmisor('nadaQueMandar');
      for (var i = 0; i < maximoPorVuelta; i++) {
        final r = await _unaVuelta(forzar: forzar && i == 0);
        ultimo = r;
        if (r.que != 'enviado' && r.que != 'rechazado' && r.que != 'resincronizado') break;
        if (r.que == 'resincronizado') continue;
        // Aceptado o rechazado: si queda un lote lleno esperando, se sigue. Si no, basta.
        final c = configuracion();
        if (await cola.contarPendientes() < c.lotePuntos) break;
      }
      return ultimo;
    } finally {
      _ocupado = false;
    }
  }

  Future<ResultadoDelEmisor> _unaVuelta({required bool forzar}) async {
    final ahora = _ahora();
    final noAntes = _noAntesDe;
    if (noAntes != null && ahora.isBefore(noAntes)) {
      return ResultadoDelEmisor('esperando', proximoIntento: noAntes);
    }

    var lote = await cola.loteEnVuelo();
    if (lote == null) {
      final armado = await _armarSiToca(forzar: forzar);
      if (armado == null) return const ResultadoDelEmisor('nadaQueMandar');
      lote = await cola.loteEnVuelo();
      if (lote == null) return const ResultadoDelEmisor('nadaQueMandar');
    }

    _envios.removeWhere((e) => ahora.difference(e) >= const Duration(minutes: 1));
    if (_envios.length >= maximoPorMinuto) {
      final cuando = _envios.first.add(const Duration(minutes: 1));
      return ResultadoDelEmisor('esperando', proximoIntento: cuando);
    }

    if (await cola.leer('claveRegistrada') != 'si') {
      if (!await registrarClave()) {
        return _fallo(lote.loteId, null, null);
      }
    }

    _envios.add(_ahora());
    final r = await api.enviarLote(lote.cuerpo);
    await cola.anotarIntento(lote.loteId, r.codigo, r.cuerpo ?? r.error,
        _ahora().millisecondsSinceEpoch);
    await cola.escribir(
        'ultimoEnvio',
        '${_ahora().millisecondsSinceEpoch}|${lote.loteId}|${r.codigo ?? '-'}|'
            '${r.cuerpo ?? r.error ?? ''}');

    final codigo = r.codigo;
    if (r.aceptado) {
      await cola.marcarAceptado(lote.loteId, lote.hash);
      await cola.purgarLoEnviado(_ahora().millisecondsSinceEpoch);
      _fallosSeguidos = 0;
      _rechazosDeFirma = 0;
      _noAntesDe = null;
      _esperaEsPorRetryAfter = false;
      return ResultadoDelEmisor('enviado', loteId: lote.loteId, codigo: codigo);
    }
    final error = _errorDe(r.cuerpo);
    // 409 cadena_rota: la ingesta tiene otro último hash (se perdió una respuesta, se
    // restauró el teléfono). Los bytes firmados no se pueden cambiar, así que el lote se
    // DESARMA —sus puntos vuelven a esperar— y se arma otro encadenado al hash que dice la
    // ingesta. No se pierde un punto.
    if (codigo == 409 && error.codigo == 'cadena_rota' && error.ultimoHash != null) {
      await cola.resincronizarCadena(lote.loteId, error.ultimoHash!);
      return ResultadoDelEmisor('resincronizado', loteId: lote.loteId, codigo: codigo);
    }
    // 429, 409 en_proceso, 503: el MISMO lote, después de lo que diga Retry-After.
    if (codigo == 429 || (codigo == 409 && error.codigo == 'en_proceso')) {
      return _fallo(lote.loteId, codigo, r.reintentarEn);
    }
    // 401 hash_no_coincide / firma_invalida: es un defecto nuestro, reintentar los mismos
    // bytes da lo mismo. Se guarda para el diagnóstico.
    if (codigo == 401 && (error.codigo == 'hash_no_coincide' || error.codigo == 'firma_invalida')) {
      await cola.marcarRechazado(lote.loteId);
      return ResultadoDelEmisor('rechazado', loteId: lote.loteId, codigo: codigo);
    }
    // 401 clave_desconocida (o sin motivo): registrar la clave y reenviar.
    if (codigo == 401) {
      _rechazosDeFirma++;
      await cola.escribir('claveRegistrada', null);
      if (_rechazosDeFirma >= maximo401) {
        _rechazosDeFirma = 0;
        await cola.marcarRechazado(lote.loteId);
        return ResultadoDelEmisor('rechazado', loteId: lote.loteId, codigo: codigo);
      }
      return _fallo(lote.loteId, codigo, null);
    }
    if (codigo == null || codigo >= 500 || codigo == 408) {
      return _fallo(lote.loteId, codigo, r.reintentarEn);
    }
    // Otro 4xx: los mismos bytes van a dar lo mismo.
    await cola.marcarRechazado(lote.loteId);
    return ResultadoDelEmisor('rechazado', loteId: lote.loteId, codigo: codigo);
  }

  ResultadoDelEmisor _fallo(String loteId, int? codigo, Duration? retryAfter) {
    _fallosSeguidos++;
    Duration espera;
    if (retryAfter != null) {
      espera = retryAfter > techoRetryAfter ? techoRetryAfter : retryAfter;
      _esperaEsPorRetryAfter = true;
    } else {
      espera = esperaTrasFallo(_fallosSeguidos, azar: _azar);
      _esperaEsPorRetryAfter = codigo == 429;
    }
    _noAntesDe = _ahora().add(espera);
    return ResultadoDelEmisor('reintentar',
        loteId: loteId, codigo: codigo, proximoIntento: _noAntesDe);
  }

  /// Arma el lote siguiente si toca. Devuelve su id, o `null` si no tocaba.
  Future<String?> _armarSiToca({required bool forzar}) async {
    final c = configuracion();
    final n = await cola.contarPendientes();
    if (n == 0) return null;
    if (!forzar && n < c.lotePuntos) {
      final viejo = await cola.tDelMasViejoPendiente();
      if (viejo == null) return null;
      final espera = _ahora().millisecondsSinceEpoch - viejo;
      if (espera < loteSeg() * 1000) return null;
    }
    final puntos = await cola.pendientes(c.lotePuntos);
    if (puntos.isEmpty) return null;
    final pts = [for (final p in puntos) p.punto];
    int? gnss;
    for (final p in pts) {
      if (gnss == null || p.t > gnss) gnss = p.t;
    }
    final l = await armarLote(
      instalacionId: instalacionId,
      loteId: nuevoUuid(),
      hashAnterior: await cola.ultimoHashAceptado(),
      reloj: await reloj(gnss),
      puntos: pts,
      firmador: firmador,
    );
    await cola.guardarLote(l, [for (final p in puntos) p.id], _ahora().millisecondsSinceEpoch);
    return l.loteId;
  }
}

/// El motivo que la ingesta pone en `error` (RESUMEN-B §5.3), y lo que haga falta de él.
({String? codigo, String? ultimoHash}) _errorDe(String? cuerpo) {
  if (cuerpo == null || cuerpo.isEmpty) return (codigo: null, ultimoHash: null);
  try {
    final j = jsonDecode(cuerpo);
    if (j is! Map) return (codigo: null, ultimoHash: null);
    final u = j['ultimoHash'];
    return (
      codigo: j['error'] is String ? j['error'] as String : null,
      ultimoHash: u is String && RegExp(r'^([0-9a-f]{64}|0)$').hasMatch(u) ? u : null,
    );
  } catch (_) {
    return (codigo: null, ultimoHash: null);
  }
}
