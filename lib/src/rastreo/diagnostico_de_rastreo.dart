/// Lo que `Rastreo` devuelve al enrolar y lo que muestra su diagnóstico. Vive aparte de
/// `rastreo.dart` sólo por tamaño; `rastreo.dart` lo reexporta.
library;

import 'cadencia.dart';
import 'cola_de_rastreo.dart';
import 'configuracion_de_rastreo.dart';
import 'detector_de_movimiento.dart';
import 'golpe/sucesos_del_aparato.dart';
import 'nativo_de_rastreo.dart';
import 'sin_gps.dart';

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
    this.motivoSinGps,
    this.huecosConMotivo = const [],
    this.medioDeclarado,
    this.sucesosPendientes = 0,
    this.ultimoSuceso,
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

  /// Por qué no hay GPS AHORA, o `null` si lo hay (o no se espera: quieto).
  final MotivoSinGps? motivoSinGps;

  /// Los [huecos] con su motivo (sólo local: el contrato del lote no lo lleva).
  final List<({Hueco hueco, MotivoSinGps motivo})> huecosConMotivo;

  /// El medio declarado para el viaje, o `null` (manda el del perfil).
  final String? medioDeclarado;

  /// Sucesos que esperan en la cola (sin red, o el servidor pidió esperar).
  final int sucesosPendientes;

  /// El último suceso que concluyó el aparato en esta sesión.
  final SucesoDelAparato? ultimoSuceso;
}
