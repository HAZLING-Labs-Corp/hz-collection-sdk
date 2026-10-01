/// EL MÓDULO RASTREO — mide a una persona por su aparato mientras se mueve, y lo manda
/// firmado. **Capta; nunca decide qué significa** (PM-026 §1).
///
/// ```dart
/// final rastreo = await Rastreo.abrir(llave: 'pk_…', url: 'https://…');
/// await rastreo.enrolar(sujetoId: 'persona-123');   // una vez
/// await rastreo.iniciar();                          // en cada arranque
/// ```
///
/// ══ QUÉ HACE, EN ORDEN ══
///
///  1. **Enrolar**: crea la clave ES256 del aparato (Keystore / Secure Enclave), enlaza la
///     instalación con su sujeto y registra la pública en `POST /api/v1/rastreo/claves`.
///  2. **Leer la configuración**: el bloque `rastreo` de `GET /api/v1/configuracion`. Si
///     dice `activo: false` —o no dice nada— no se mide. Se relee cada hora.
///  3. **Detectar solo el movimiento** con la captura elegida (propia o Transistor).
///  4. **Grabar** cada punto en la cola SQLite — nunca un request por punto.
///  5. **Mandar lotes firmados** (`POST /api/v1/rastreo/lotes`) cada `loteSeg` de la fila
///     de cadencia vigente o al llegar a `lotePuntos`, con la espera creciente, el
///     `Retry-After` y la cadena de hashes.
///
/// ══ LO QUE NO HACE (y es de otras rebanadas) ══
///
/// Presencia, latidos, sucesos urgentes, «¿estás bien?», SMS. La tabla de cadencia trae sus
/// números (`presenciaSeg`, `latidoMin`) y el bloque trae `golpe`: se leen y se muestran,
/// pero nada los usa todavía.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../remote_config.dart';
import '../sujeto.dart';
import 'api_de_rastreo.dart';
import 'cadencia.dart';
import 'captura.dart';
import 'cola_de_rastreo.dart';
import 'configuracion_de_rastreo.dart';
import 'punto.dart';
import 'detector_de_movimiento.dart';
import 'emisor_de_lotes.dart';
import 'lote.dart';
import 'medidor_de_hilo.dart';
import 'nativo_de_rastreo.dart';

/// Cómo salió cada paso del enrolamiento. Los tres son independientes: que el sujeto no se
/// haya podido enlazar no impide registrar la clave, y se ve cuál falló.
class ResultadoDeEnrolamiento {
  const ResultadoDeEnrolamiento({
    required this.instalacionId,
    required this.claveId,
    required this.enHardware,
    required this.instalacion,
    required this.sujeto,
    required this.clave,
  });

  final String instalacionId;
  final String claveId;
  final bool enHardware;

  /// `null` si salió bien; si no, por qué.
  final String? instalacion;
  final String? sujeto;
  final String? clave;

  bool get completo => instalacion == null && sujeto == null && clave == null;

  @override
  String toString() => completo
      ? 'enrolado: $instalacionId · clave $claveId'
      : 'enrolamiento incompleto — instalación: ${instalacion ?? 'bien'} · '
          'sujeto: ${sujeto ?? 'bien'} · clave: ${clave ?? 'bien'}';
}

/// Todo lo que la pantalla de diagnóstico muestra, leído de una vez.
class DiagnosticoDeRastreo {
  const DiagnosticoDeRastreo({
    required this.instalacionId,
    required this.sujetoId,
    required this.claveId,
    required this.claveEnHardware,
    required this.claveRegistrada,
    required this.configuracion,
    required this.configuracionCodigo,
    required this.configuracionCuando,
    required this.captura,
    required this.capturaActiva,
    required this.cadencia,
    required this.estado,
    required this.motivoDelEstado,
    required this.permiso,
    required this.gpsPrendido,
    required this.energia,
    required this.enCola,
    required this.colaBytes,
    required this.lotesAceptados,
    required this.lotesRechazados,
    required this.ultimoEnvio,
    required this.loteEnVuelo,
    required this.proximoIntento,
    required this.fallosSeguidos,
    required this.descartados,
    required this.huecos,
    required this.problemas,
  });

  final String instalacionId;
  final String? sujetoId;
  final String? claveId;
  final bool claveEnHardware;
  final bool claveRegistrada;
  final ConfiguracionDeRastreo configuracion;
  final int? configuracionCodigo;
  final DateTime? configuracionCuando;
  final String captura;
  final bool capturaActiva;

  /// La fila de la tabla de cadencia que manda ahora.
  final FilaDeCadencia cadencia;
  final EstadoDeMovimiento estado;
  final String? motivoDelEstado;

  /// `siempre` · `enUso` · `no` — con los nombres de PM-025 §4.3.
  final String permiso;
  final bool gpsPrendido;
  final EnergiaDelAparato energia;
  final int enCola;
  final int colaBytes;
  final int lotesAceptados;
  final int lotesRechazados;

  /// El último intento de envío: cuándo, qué lote, qué código y qué contestó.
  final ({DateTime cuando, String loteId, String codigo, String respuesta})? ultimoEnvio;
  final String? loteEnVuelo;
  final DateTime? proximoIntento;
  final int fallosSeguidos;
  final int descartados;
  final List<Hueco> huecos;
  final List<String> problemas;
}

class Rastreo {
  Rastreo._({
    required this.api,
    required this.apiDelNucleo,
    required this.cola,
    required this.captura,
    required this.instalacionId,
    required this.paquete,
    required SharedPreferences prefs,
  }) : _prefs = prefs {
    final guardada = _prefs.getString(_claveConfig);
    if (guardada != null) {
      try {
        _config = ConfiguracionDeRastreo.fromJson(
            (jsonDecode(guardada) as Map).cast<String, dynamic>());
      } catch (_) {}
    }
    _sujetoId = _prefs.getString(_claveSujeto);
  }

  static const _claveConfig = 'akpush.rastreo.config';
  static const _claveSujeto = 'akpush.rastreo.sujeto';
  static const _claveArranque = 'akpush.rastreo.arranque';

  final ApiDeRastreo api;
  final AkPushApi apiDelNucleo;
  final ColaDeRastreo cola;
  final CapturaDeRastreo captura;
  final String instalacionId;
  final String paquete;
  final SharedPreferences _prefs;

  ConfiguracionDeRastreo _config = ConfiguracionDeRastreo.apagada;
  ConfiguracionDeRastreo get configuracion => _config;
  int? _configCodigo;
  DateTime? _configCuando;
  String? _sujetoId;
  ClaveDelAparato? _clave;
  EmisorDeLotes? _emisor;
  StreamSubscription<EventoDeCaptura>? _eventos;
  StreamSubscription<List<ConnectivityResult>>? _red;
  Timer? _reloj;
  Timer? _despertador;
  AppLifecycleListener? _ciclo;
  Timer? _relecturaDeConfig;
  String? _motivo;
  final List<String> _problemas = [];
  int? _ultimoTDelTramo;
  int? _tramoDelUltimo;
  final int _sesion = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  final _cambios = StreamController<void>.broadcast();

  /// Avisa cada vez que algo cambió (un punto, un envío, un estado). Para refrescar una
  /// pantalla sin sondear.
  Stream<void> get cambios => _cambios.stream;

  /// Abre el módulo. No mide nada todavía: eso es [iniciar].
  ///
  /// [url] es la API de Collection; [urlIngesta], la del proceso de ingesta si está en otra
  /// dirección (en local: la API en :3085 y la ingesta en :8080).
  static Future<Rastreo> abrir({
    required String llave,
    required String url,
    String? urlIngesta,
    CapturaDeRastreo? captura,
    http.Client? cliente,
    ColaDeRastreo? cola,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final instalacionId = await ConfigStore().leerOCrearInstalacionId();
    final paquete = (await PackageInfo.fromPlatform()).packageName;
    return Rastreo._(
      api: ApiDeRastreo(llave: llave, url: url, urlIngesta: urlIngesta, cliente: cliente),
      apiDelNucleo: AkPushApi(apiKey: llave, baseUrl: AkPushApi.normalizarUrl(url), cliente: cliente),
      cola: cola ?? await ColaDeRastreo.abrir(),
      captura: captura ?? CapturaPropia(),
      instalacionId: instalacionId,
      paquete: paquete,
      prefs: prefs,
    );
  }

  String? get sujetoId => _sujetoId;

  /// ENROLAR: la clave, la instalación, el sujeto y el registro de la pública.
  ///
  /// Idempotente: la clave se crea sólo si no existe, y los tres POST son altas-o-
  /// actualización del otro lado. Llamarlo en cada arranque no duplica nada.
  Future<ResultadoDeEnrolamiento> enrolar({required String sujetoId}) async {
    final clave = _clave = await ClaveDelAparato.asegurar();
    String? errInstalacion, errSujeto, errClave;
    try {
      await apiDelNucleo.registrarInstalacion(
        instalacionId: instalacionId,
        aparato: {'plataforma': defaultTargetPlatform.name},
        sujetoId: sujetoId,
      );
    } catch (e) {
      errInstalacion = '$e';
    }
    try {
      await apiDelNucleo.registrarSujeto(
        sujetoId: sujetoId,
        tipo: TipoDeSujeto.natural,
        instalacionId: instalacionId,
      );
    } catch (e) {
      errSujeto = '$e';
    }
    _sujetoId = sujetoId;
    await _prefs.setString(_claveSujeto, sujetoId);
    if (!await _registrarClave()) {
      errClave = await cola.leer('claveError') ?? 'no se pudo registrar';
    }
    _cambios.add(null);
    return ResultadoDeEnrolamiento(
      instalacionId: instalacionId,
      claveId: clave.claveId,
      enHardware: clave.enHardware,
      instalacion: errInstalacion,
      sujeto: errSujeto,
      clave: errClave,
    );
  }

  Future<bool> _registrarClave() async {
    final clave = _clave ??= await ClaveDelAparato.asegurar();
    final r = await api.registrarClave(
      instalacionId: instalacionId,
      claveId: clave.claveId,
      publicaSpkiBase64: clave.publicaSpkiBase64,
    );
    if (r.aceptado) {
      await cola.escribir('claveRegistrada', 'si');
      await cola.escribir('claveError', null);
      return true;
    }
    await cola.escribir('claveError', '${r.codigo ?? 'sin red'}: ${r.cuerpo ?? r.error ?? ''}');
    return false;
  }

  /// Relee el bloque `rastreo`. Si no llega, se queda con el último guardado; si nunca
  /// llegó ninguno, apagado.
  Future<ConfiguracionDeRastreo> releerConfiguracion() async {
    final (bloque, r) = await api.leerConfiguracion(paquete);
    _configCodigo = r.codigo;
    _configCuando = DateTime.now();
    if (r.aceptado) {
      // Llegó la configuración. Si no trae el bloque, el comercio no tiene rastreo: apagado.
      _config = ConfiguracionDeRastreo.fromJson(bloque);
      final ingesta = bloque?['ingestaUrl'];
      api.usarIngestaDelServidor(ingesta is String ? ingesta : null);
      await _prefs.setString(_claveConfig, jsonEncode(_config.toJson()));
    }
    _cambios.add(null);
    return _config;
  }

  /// ARRANCA: lee la configuración y, si `activo`, prende la captura. Se llama en cada
  /// arranque de la aplicación.
  Future<String?> iniciar() async {
    // UNA SOLA CAPTURA VIVA POR PROCESO: si otro `Rastreo` de este proceso sigue corriendo (la
    // pantalla se abrió de nuevo y armó uno nuevo), se detiene antes. Sin esto cada instancia abre
    // su propio GPS y cada punto se graba N veces (medido: 118 puntos en el servidor contra 41 reales).
    final otro = _vivo;
    if (otro != null && !identical(otro, this)) {
      try {
        await otro.detener();
      } catch (_) {}
    }
    _vivo = this;
    _clave ??= await ClaveDelAparato.asegurar();
    _emisor ??= EmisorDeLotes(
      cola: cola,
      api: api,
      firmador: _clave!,
      instalacionId: instalacionId,
      reloj: _relojDelLote,
      configuracion: () => _config,
      loteSeg: () => captura.cadencia.loteSeg ?? FilaDeCadencia.respaldo.loteSeg!,
      registrarClave: _registrarClave,
    );
    await releerConfiguracion();

    _eventos ??= captura.eventos.listen(_alEvento);
    // RECUPERACIÓN RÁPIDA: al volver la red o al pasar a primer plano se olvida la espera
    // creciente y se intenta a un azar de 0 a 15 s (no a los 30 min del tope).
    _red ??= Connectivity().onConnectivityChanged.listen((r) {
      if (r.any((x) => x != ConnectivityResult.none)) _recuperar();
    });
    _ciclo ??= AppLifecycleListener(onResume: _recuperar);
    // El reloj del emisor: reintentos mientras la persona está quieta (no llegan puntos que
    // lo despierten). Un intento que está esperando no toca la red: cuesta una consulta a
    // SQLite.
    _reloj ??= Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_intentarEnviar()));
    _relecturaDeConfig ??=
        Timer.periodic(const Duration(hours: 1), (_) => unawaited(_aplicarConfiguracion()));

    final motivo = await _aplicarConfiguracion(releer: false);
    unawaited(_intentarEnviar());
    if (motivo == null) {
      unawaited(_presenciaQuieta(primera: true));
      _relojDePresencia ??= Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_presenciaQuieta()));
    }
    return motivo;
  }

  /// Aplica la configuración vigente: prende o apaga la captura.
  Future<String?> _aplicarConfiguracion({bool releer = true}) async {
    if (releer) await releerConfiguracion();
    if (!_config.activo) {
      if (captura.activa) await captura.detener();
      _motivo = 'la configuración dice activo: false';
      _cambios.add(null);
      // Lo que ya se midió se manda igual: se midió cuando estaba activo.
      unawaited(_intentarEnviar(forzar: true));
      return _motivo;
    }
    final no = await captura.iniciar(_config);
    _motivo = no;
    if (no != null) _anotarProblema(no);
    _cambios.add(null);
    return no;
  }

  Future<void> detener() async {
    if (identical(_vivo, this)) _vivo = null;
    await captura.detener();
    _reloj?.cancel();
    _relojDePresencia?.cancel();
    _relojDePresencia = null;
    _reloj = null;
    _despertador?.cancel();
    _despertador = null;
    _ciclo?.dispose();
    _ciclo = null;
    _relecturaDeConfig?.cancel();
    _relecturaDeConfig = null;
    await _red?.cancel();
    _red = null;
    await _eventos?.cancel();
    _eventos = null;
    _motivo = 'detenido';
    _cambios.add(null);
  }

  /// Arma y manda lo que haya, sin esperar los cinco minutos. Respeta la espera.
  Future<ResultadoDelEmisor?> enviarAhora() => _intentarEnviar(forzar: true);

  Future<ResultadoDelEmisor?> _intentarEnviar({bool forzar = false}) async {
    final e = _emisor;
    if (e == null) return null;
    final r = await e.intentar(forzar: forzar);
    if (r.que != 'nadaQueMandar' && r.que != 'esperando') _cambios.add(null);
    _despertarEn(r.proximoIntento);
    return r;
  }

  /// Programa un intento justo cuando termina la espera. Sin esto, el intento caería en el
  /// siguiente tic de 30 s del reloj y el azar de la espera quedaría redondeado a ese tic.
  void _despertarEn(DateTime? cuando) {
    if (cuando == null || _reloj == null) return;
    final falta = cuando.difference(DateTime.now());
    _despertador?.cancel();
    _despertador = Timer(falta.isNegative ? Duration.zero : falta + const Duration(milliseconds: 50),
        () => unawaited(_intentarEnviar()));
  }

  void _recuperar() {
    final e = _emisor;
    if (e == null) return;
    _despertarEn(e.reiniciarEspera());
    _cambios.add(null);
  }

  int _presenciaT = 0;

  /// La presencia sale cada `presenciaSeg` de la fila de cadencia que manda (0 → no sale): la
  /// cadencia es dato, el SDK sólo la cumple. Es la que alimenta la «Flota en vivo» (§4.2).
  /// Sin red o con error no se reintenta: la siguiente ya lleva una posición más nueva.
  /// El único `Rastreo` de este proceso que está corriendo (ver `iniciar`).
  static Rastreo? _vivo;

  Timer? _relojDePresencia;

  /// PRESENCIA SIN RUTA: la flota tiene que decir DÓNDE está un aparato aunque no haya empezado a
  /// moverse ni a grabar. Al arrancar manda una vez la posición conocida, y mientras está quieto
  /// (la captura grabando nada, GPS apagado) repite esa posición cada `presenciaSeg` de la fila que
  /// manda —o su `latidoMin` si la fila no tiene presencia—, nunca menos de 15 s. Es una lectura
  /// de caché del sistema: no prende el GPS.
  Future<void> _presenciaQuieta({bool primera = false}) async {
    final fila = captura.cadencia;
    final base = fila.presenciaSeg > 0
        ? fila.presenciaSeg
        : (_config.presenciaQuietoSeg > 0 ? _config.presenciaQuietoSeg : (fila.latidoMin ?? 30) * 60);
    final cada = math.max(10, base);
    final ahora = DateTime.now().millisecondsSinceEpoch;
    if (kDebugMode || MedidorDeHilo.activo) {
      if (ahora - _ultimoRastroDePresencia > 20000) {
        _ultimoRastroDePresencia = ahora;
        debugPrint('HzRastreoPresencia activo=${_config.activo} capturaActiva=${captura.activa} captura=${captura.nombre} estado=${captura.estado.name} fila=${fila.estado} presenciaSeg=${fila.presenciaSeg} cada=$cada desdeLaUltima=${(ahora - _presenciaT) ~/ 1000}s');
      }
    }
    if (!_config.activo || !captura.activa) return;
    if (!primera && captura.estado == EstadoDeMovimiento.rodando) return; // la manda cada punto
    if (!primera && ahora - _presenciaT < cada * 1000) return;
    try {
      final p = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 10)));
      int bat = -1;
      try {
        bat = await Battery().batteryLevel;
      } catch (_) {}
      _presenciaT = ahora;
      final r = await api.enviarPresencia({
        'instalacionId': instalacionId,
        't': ahora,
        'lat': p.latitude,
        'lon': p.longitude,
        'acc': p.accuracy < 0 ? 0 : p.accuracy,
        'v': p.speed < 0 ? 0 : p.speed,
        'h': (p.hasHeading && p.heading >= 0 && p.heading < 360) ? p.heading : PuntoDeRastreo.rumboDesconocido,
        'estado': captura.estado == EstadoDeMovimiento.rodando ? 'rodando' : 'detenido',
        'bat': (bat < 0 || bat > 100) ? -1 : bat,
      });
      if (!r.aceptado) _anotarProblema('presencia: ${r.codigo ?? 'sin red'}');
    } catch (e) {
      // se anota una vez por minuto como mucho: un error que se repite cada 5 s llenaría el diagnóstico
      if (DateTime.now().millisecondsSinceEpoch - _ultimoAvisoDePresencia > 60000) {
        _ultimoAvisoDePresencia = DateTime.now().millisecondsSinceEpoch;
        _anotarProblema('presencia sin posición: $e');
      }
    }
  }

  int _ultimoAvisoDePresencia = 0;
  int _ultimoRastroDePresencia = 0;

  Future<void> _mandarPresencia(PuntoDeRastreo p) async {
    final cada = captura.cadencia.presenciaSeg;
    if (cada <= 0) return;
    final ahora = DateTime.now().millisecondsSinceEpoch;
    if (ahora - _presenciaT < cada * 1000) return;
    _presenciaT = ahora;
    try {
      final r = await api.enviarPresencia({
        'instalacionId': instalacionId,
        't': p.t,
        'lat': p.lat,
        'lon': p.lon,
        'acc': p.acc,
        'v': p.v,
        'h': p.h,
        'estado': captura.estado == EstadoDeMovimiento.rodando ? 'rodando' : 'detenido',
        'bat': p.bat,
      });
      if (!r.aceptado) _anotarProblema('presencia: ${r.codigo ?? 'sin red'}');
    } catch (_) {}
  }

  Future<void> _alEvento(EventoDeCaptura ev) async {
    switch (ev) {
      case PuntoCapturado(:final punto, tramo: final tramoDeLaCaptura, :final hueco):
        // El número de tramo de la captura vuelve a 1 en cada arranque; en la cola tiene que
        // ser único, o dos viajes de dos días distintos serían «el mismo tramo».
        final tramo = _sesion * 1000 + tramoDeLaCaptura;
        await cola.agregar(punto, tramo);
        // El hueco lo informa la captura propia (su detector sabe el ritmo esperado); para
        // otra captura se calcula acá con el último punto del mismo tramo.
        var h = hueco;
        if (h == null && captura is! CapturaPropia &&
            _tramoDelUltimo == tramo && _ultimoTDelTramo != null) {
          if (punto.t - _ultimoTDelTramo! > const Duration(minutes: 1).inMilliseconds) {
            h = (_ultimoTDelTramo!, punto.t);
          }
        }
        if (h != null) await cola.anotarHueco(h.$1, h.$2, tramo);
        _tramoDelUltimo = tramo;
        _ultimoTDelTramo = punto.t;
        _cambios.add(null);
        unawaited(_mandarPresencia(punto));
        unawaited(_intentarEnviar());
      case CambioDeEstado(:final motivo, :final vaciar):
        _motivo = motivo;
        _cambios.add(null);
        // Siempre se mira el emisor: una fila nueva puede traer un `loteSeg` más corto.
        unawaited(_intentarEnviar(forzar: vaciar));
      case ProblemaDeCaptura(:final descripcion):
        _anotarProblema(descripcion);
    }
  }

  void _anotarProblema(String p) {
    final linea = '${DateTime.now().toIso8601String().substring(11, 19)}  $p';
    _problemas.insert(0, linea);
    if (_problemas.length > 20) _problemas.removeLast();
    _cambios.add(null);
  }

  /// Los relojes del lote. Si el sistema no cuenta arranques (iPhone), se cuentan acá:
  /// cada vez que la hora de arranque estimada (ahora − mono) se mueve más de un minuto,
  /// es un arranque nuevo.
  Future<RelojDelLote> _relojDelLote(int? gnss) async {
    final r = await RelojDelAparato.leer();
    var arranques = r.arranques;
    if (arranques == null) {
      final arranqueAhora = DateTime.now().millisecondsSinceEpoch - r.mono;
      final guardado = _prefs.getString(_claveArranque)?.split('|');
      var n = guardado != null ? int.tryParse(guardado[1]) ?? 1 : 1;
      final antes = guardado != null ? int.tryParse(guardado[0]) : null;
      if (antes != null && (arranqueAhora - antes).abs() > 60000) n++;
      await _prefs.setString(_claveArranque, '$arranqueAhora|$n');
      arranques = n;
    }
    return RelojDelLote(mono: r.mono, arranques: arranques, gnss: gnss);
  }

  /// Lo que muestra la pantalla de diagnóstico. Son ~12 consultas a SQLite y ~5 viajes al
  /// nativo: todas con `await`, ninguna bloquea el hilo; se mide igual (`MedidorDeHilo`).
  Future<DiagnosticoDeRastreo> diagnostico() =>
      MedidorDeHilo.asincrono('diagnostico', _diagnostico);

  Future<DiagnosticoDeRastreo> _diagnostico() async {
    final permiso = await Geolocator.checkPermission();
    final t = await cola.tamano();
    final l = await cola.contarLotes();
    final u = (await cola.leer('ultimoEnvio'))?.split('|');
    final enVuelo = await cola.loteEnVuelo();
    return DiagnosticoDeRastreo(
      instalacionId: instalacionId,
      sujetoId: _sujetoId,
      claveId: _clave?.claveId,
      claveEnHardware: _clave?.enHardware ?? false,
      claveRegistrada: await cola.leer('claveRegistrada') == 'si',
      configuracion: _config,
      configuracionCodigo: _configCodigo,
      configuracionCuando: _configCuando,
      captura: captura.nombre,
      capturaActiva: captura.activa,
      cadencia: captura.cadencia,
      estado: captura.estado,
      motivoDelEstado: _motivo,
      permiso: switch (permiso) {
        LocationPermission.always => 'siempre',
        LocationPermission.whileInUse => 'enUso',
        _ => 'no',
      },
      gpsPrendido: await Geolocator.isLocationServiceEnabled(),
      energia: await EnergiaDelAparato.leer(),
      enCola: await cola.contarPendientes(),
      colaBytes: t.bytes,
      lotesAceptados: l.aceptados,
      lotesRechazados: l.rechazados,
      ultimoEnvio: (u == null || u.length < 4)
          ? null
          : (
              cuando: DateTime.fromMillisecondsSinceEpoch(int.tryParse(u[0]) ?? 0),
              loteId: u[1],
              codigo: u[2],
              respuesta: u.sublist(3).join('|'),
            ),
      loteEnVuelo: enVuelo?.loteId,
      proximoIntento: _emisor?.proximoIntento,
      fallosSeguidos: _emisor?.fallosSeguidos ?? 0,
      descartados: await cola.descartados(),
      huecos: await cola.huecosDesde(
          DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch),
      problemas: List.unmodifiable(_problemas),
    );
  }
}
