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
/// | 429 | `Retry-After` (techo 1 h) + azar entre 0 y ese mismo `Retry-After`; o la espera creciente si no lo dice |
/// | 5xx, 408, sin red | espera creciente con JITTER COMPLETO: azar entre 0 y el tope (30 s, 1, 2, 4… techo 30 min) |
/// | 409 `en_proceso` | el mismo lote después de `Retry-After` + azar (otra petición lo está escribiendo) |
/// | 409 `cadena_rota` | se DESARMA el lote (sus puntos vuelven a la cola) y se encadena al `ultimoHash` que manda la ingesta |
/// | 401 `clave_desconocida` | se re-registra la clave y se reintenta el MISMO lote; al tercer 401, rechazado |
/// | 403 `rastreo_apagado` / `medicion_apagada` | el SERVIDOR apagó el rastreo: el lote NO se rechaza ni se reintenta; el emisor queda `apagado` (no manda nada) hasta [reanudar]. Ver `apagado_del_servidor.dart` |
/// | 401 `hash_no_coincide` / `firma_invalida`, otro 4xx | rechazado: los mismos bytes van a dar lo mismo. Se guarda para el diagnóstico |
///
/// Y un techo propio: a lo sumo 5 lotes por minuto (la ingesta corta en 6).
///
/// 🔴 **El azar de la espera no es un adorno, y ±20 % no alcanza (contrato §4.12).** Un
/// millón de teléfonos que perdieron el servidor a la vez —una caída de la ingesta, un
/// corte de la operadora— fallan a la vez. Con ±20 % sobre 30 s vuelven todos entre los
/// 24 y los 36 s: ~83 mil requests por segundo durante 12 s. Con JITTER COMPLETO (azar
/// entre 0 y el tope) se reparten en toda la espera, y cada ronda siguiente se reparte en
/// una ventana el doble de ancha. La cifra medida está en `test/rastreo/jitter_test.dart`.
///
/// ══ RECUPERACIÓN RÁPIDA ══
///
/// Cuando vuelve la red o la app pasa a primer plano, [reiniciarEspera] olvida la espera
/// creciente y deja el próximo intento a un azar corto de 0 a [ventanaDeRecuperacion]
/// (15 s): si la red nunca se cortó de verdad, no hay por qué esperar hasta 30 min. Un
/// `Retry-After` vigente NO se olvida: lo pidió el servidor, y la red del teléfono no
/// cambia lo que le pasa al servidor.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'apagado_del_servidor.dart';
import 'api_de_rastreo.dart';
import 'cola_de_rastreo.dart';
import 'etiquetas/etiquetas_ble.dart';
import 'configuracion_de_rastreo.dart';
import 'lote.dart';
import 'medidor_de_hilo.dart';

/// Lo que pasó en un intento, para el diagnóstico.
class ResultadoDelEmisor {
  const ResultadoDelEmisor(this.que, {this.loteId, this.codigo, this.proximoIntento});

  /// `nadaQueMandar` · `esperando` · `enviado` · `reintentar` · `rechazado` · `resincronizado` ·
  /// `apagado` (el servidor apagó el rastreo: 403 `rastreo_apagado` / `medicion_apagada`).
  final String que;
  final String? loteId;
  final int? codigo;
  final DateTime? proximoIntento;

  @override
  String toString() => 'ResultadoDelEmisor($que, lote: $loteId, código: $codigo, '
      'próximo: $proximoIntento)';
}

/// El TOPE de la espera tras [fallos] fallos seguidos (1 = el primero): 30 s, 1, 2, 4…
/// minutos, con techo de 30 min. Es el techo del azar, no la espera.
Duration topeTrasFallo(int fallos) {
  const base = 30; // segundos
  const techo = 30 * 60;
  final exp = fallos <= 1 ? 0 : (fallos - 1).clamp(0, 16);
  return Duration(seconds: math.min(techo, base * math.pow(2, exp).toInt()));
}

/// Un azar uniforme en [0, max], en milisegundos.
Duration _azarHasta(Duration max, math.Random azar) =>
    Duration(milliseconds: (azar.nextDouble() * max.inMilliseconds).round());

/// La espera tras [fallos] fallos seguidos, con JITTER COMPLETO: uniforme entre 0 y
/// [topeTrasFallo] (contrato §4.12). Nunca ±20 %. Pura, para poder probarla.
Duration esperaTrasFallo(int fallos, {math.Random? azar}) =>
    _azarHasta(topeTrasFallo(fallos), azar ?? math.Random());

/// La espera cuando el servidor dijo `Retry-After`: lo que pidió (con techo) más un azar
/// entre 0 y eso mismo. Sin el azar, un millón que recibieron `Retry-After: 60` en el
/// mismo segundo volverían todos en el mismo segundo 60.
Duration esperaTrasRetryAfter(Duration retryAfter,
    {Duration techo = const Duration(hours: 1), math.Random? azar}) {
  final ra = retryAfter > techo ? techo : (retryAfter.isNegative ? Duration.zero : retryAfter);
  return ra + _azarHasta(ra, azar ?? math.Random());
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
    this.medio,
    this.avistamientos,
    DateTime Function()? ahora,
    math.Random? azar,
    this.ventanaDeRecuperacion = const Duration(seconds: 15),
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

  /// El medio declarado para el viaje (`Rastreo.declararMedio`), o `null`: va en el lote que
  /// se arma ahora, según la hora de su punto más viejo. Un lote ya armado no cambia (sus
  /// bytes están firmados).
  final String? Function(int? tMasViejo)? medio;

  /// Etiquetas BLE: lo oído hasta el punto más nuevo del lote que se arma (y se saca de la espera).
  final List<Avistamiento> Function(int tMasNuevo)? avistamientos;

  /// Los envíos del último minuto. La ingesta acepta a lo sumo 6 lotes por minuto por
  /// instalación (RESUMEN-B §8); el SDK se queda en [maximoPorMinuto] para no gastar un 429.
  final List<DateTime> _envios = [];
  static const maximoPorMinuto = 5;

  final DateTime Function() _ahora;
  final math.Random _azar;

  /// El azar corto de [reiniciarEspera]: el próximo intento cae entre 0 y esto.
  final Duration ventanaDeRecuperacion;

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

  bool _apagadoPorServidor = false;
  String? _motivoDelApagado;

  /// El servidor contestó 403 `rastreo_apagado` / `medicion_apagada`: no se manda nada hasta
  /// [reanudar]. Los lotes quedan en la cola tal cual (no se rechazan ni se borran).
  bool get apagadoPorServidor => _apagadoPorServidor;
  String? get motivoDelApagado => _motivoDelApagado;

  /// La configuración volvió encendida: se vuelve a mandar, empezando por el lote que esperaba.
  void reanudar() {
    _apagadoPorServidor = false;
    _motivoDelApagado = null;
    _fallosSeguidos = 0;
    _noAntesDe = null;
    _esperaEsPorRetryAfter = false;
  }

  bool _esperaEsPorRetryAfter = false;

  /// RECUPERACIÓN RÁPIDA. Se llama cuando vuelve la conectividad o la app pasa a primer
  /// plano: olvida la espera creciente y pone el próximo intento a un azar de 0 a
  /// [ventanaDeRecuperacion]. El azar existe porque la red vuelve a la vez para todos los
  /// que estaban bajo la misma antena. NO olvida un `Retry-After` vigente.
  ///
  /// Devuelve cuándo es el próximo intento (o `null` si no había nada esperando).
  DateTime? reiniciarEspera() {
    if (_esperaEsPorRetryAfter) {
      final n = _noAntesDe;
      if (n != null && _ahora().isBefore(n)) return n;
      _esperaEsPorRetryAfter = false;
    }
    _fallosSeguidos = 0;
    _noAntesDe = _ahora().add(_azarHasta(ventanaDeRecuperacion, _azar));
    return _noAntesDe;
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
    if (_apagadoPorServidor) return const ResultadoDelEmisor('apagado');
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
    final cuerpo = lote.cuerpo;
    final r = await MedidorDeHilo.asincrono('red.POST lote', () => api.enviarLote(cuerpo));
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
    // 403 rastreo_apagado / medicion_apagada: el servidor no quiere NADA ahora. No es un lote
    // malo: no se rechaza, no se reintenta en bucle; queda guardado hasta que vuelva encendido.
    if (esApagadoDelServidor(codigo, error.codigo)) {
      _apagadoPorServidor = true;
      _motivoDelApagado = error.codigo;
      return ResultadoDelEmisor('apagado', loteId: lote.loteId, codigo: codigo);
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
      espera = esperaTrasRetryAfter(retryAfter, techo: techoRetryAfter, azar: _azar);
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
    int? masViejo;
    for (final p in pts) {
      if (gnss == null || p.t > gnss) gnss = p.t;
      if (masViejo == null || p.t < masViejo) masViejo = p.t;
    }
    final l = await armarLote(
      instalacionId: instalacionId,
      loteId: nuevoUuid(),
      hashAnterior: await cola.ultimoHashAceptado(),
      reloj: await reloj(gnss),
      puntos: pts,
      firmador: firmador,
      medio: medio?.call(masViejo),
      avistamientos: avistamientos?.call(gnss!) ?? const [],
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
