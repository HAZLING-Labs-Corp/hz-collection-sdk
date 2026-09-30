// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'textos_de_rastreo.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class TextosDeRastreoEs extends TextosDeRastreo {
  TextosDeRastreoEs([String locale = 'es']) : super(locale);

  @override
  String get titulo => 'Rastreo · diagnóstico';

  @override
  String get si => 'Sí';

  @override
  String get no => 'No';

  @override
  String get sinDato => '—';

  @override
  String get seccionEnrolamiento => 'Enrolamiento';

  @override
  String get sujeto => 'Sujeto';

  @override
  String get instalacion => 'Instalación';

  @override
  String get clave => 'Clave del aparato';

  @override
  String get claveEnHardware => 'Clave en hardware';

  @override
  String get claveRegistrada => 'Registrada en la ingesta';

  @override
  String get enrolar => 'Enrolar';

  @override
  String enrolado(String clave) {
    return 'Enrolado. Clave $clave';
  }

  @override
  String enrolamientoIncompleto(String detalle) {
    return 'Enrolamiento incompleto: $detalle';
  }

  @override
  String get seccionConfiguracion => 'Configuración del servidor';

  @override
  String get activo => 'Activo';

  @override
  String get perfil => 'Perfil';

  @override
  String get respuesta => 'Respuesta';

  @override
  String get quietoTras => 'Apaga el GPS tras';

  @override
  String get arranque => 'Arranca sobre';

  @override
  String get lote => 'Lote';

  @override
  String minutos(int n) {
    return '$n min';
  }

  @override
  String kmh(int n) {
    return '$n km/h';
  }

  @override
  String get releer => 'Releer';

  @override
  String get techoLote => 'Techo de un lote';

  @override
  String puntos(int n) {
    return '$n puntos';
  }

  @override
  String get forzado => 'Estado forzado';

  @override
  String get cadenciaRespaldo =>
      'El servidor no mandó tabla de cadencia: rige el respaldo (10 s · lote 300 s).';

  @override
  String get cadenciaAhora => 'Cadencia ahora';

  @override
  String filaConGps(int m, int l) {
    return 'cada $m s · lote $l s';
  }

  @override
  String filaSinGps(int min) {
    return 'GPS apagado · latido $min min';
  }

  @override
  String get seccionPermisos => 'Permisos';

  @override
  String get ubicacion => 'Ubicación';

  @override
  String get permisoSiempre => 'Siempre';

  @override
  String get permisoEnUso => 'Sólo mientras se usa';

  @override
  String get permisoNo => 'No';

  @override
  String get gps => 'GPS del teléfono';

  @override
  String get prendido => 'Prendido';

  @override
  String get apagado => 'Apagado';

  @override
  String get actividadFisica => 'Actividad física';

  @override
  String get pedirPermisos => 'Pedir permisos';

  @override
  String get seccionBateria => 'Batería';

  @override
  String get nivel => 'Nivel';

  @override
  String porciento(int n) {
    return '$n %';
  }

  @override
  String get cargando => 'Cargando';

  @override
  String get sinRestricciones => 'Sin restricciones de batería';

  @override
  String get ahorro => 'Ahorro de energía';

  @override
  String get aparato => 'Aparato';

  @override
  String versionAndroid(int n) {
    return 'Android API $n';
  }

  @override
  String get ajustesDeBateria => 'Ajustes de batería';

  @override
  String get seccionCaptura => 'Captura';

  @override
  String get captura => 'Captura';

  @override
  String get capturaPropia => 'Propia';

  @override
  String get capturaTransistor => 'Transistor';

  @override
  String get activa => 'Activa';

  @override
  String get estado => 'Estado';

  @override
  String get motivo => 'Motivo';

  @override
  String get estadoQuieto => 'Quieto (GPS apagado)';

  @override
  String get estadoConfirmando => 'Confirmando movimiento';

  @override
  String get estadoRodando => 'Rodando (GPS preciso)';

  @override
  String get iniciar => 'Iniciar rastreo';

  @override
  String get detener => 'Detener';

  @override
  String noArranco(String motivo) {
    return 'No arrancó: $motivo';
  }

  @override
  String get seccionCola => 'Cola en el teléfono';

  @override
  String get enCola => 'Puntos en cola';

  @override
  String get tamano => 'Tamaño';

  @override
  String kb(String n) {
    return '$n KB';
  }

  @override
  String get loteEnVuelo => 'Lote en vuelo';

  @override
  String get aceptados => 'Lotes aceptados';

  @override
  String get rechazados => 'Lotes rechazados';

  @override
  String get descartados => 'Puntos descartados por techo';

  @override
  String get proximoIntento => 'Próximo intento';

  @override
  String get fallosSeguidos => 'Fallos seguidos';

  @override
  String get enviarAhora => 'Mandar ahora';

  @override
  String get seccionUltimoLote => 'Último lote enviado';

  @override
  String get cuando => 'Cuándo';

  @override
  String get codigo => 'Código';

  @override
  String get ningunLote => 'Todavía no se mandó ninguno';

  @override
  String get seccionHuecos => 'Huecos en las últimas 24 h';

  @override
  String get sinHuecos => 'Sin huecos';

  @override
  String hueco(String desde, String hasta, int seg) {
    return '$desde → $hasta · $seg s';
  }

  @override
  String get seccionProblemas => 'Problemas';

  @override
  String get sinProblemas => 'Sin problemas';

  @override
  String get seccionSimular => 'Simular recorrido';

  @override
  String get simularExplicacion =>
      'Inyecta una ruta de ~4 km como si fuera el GPS: 40 s parado, 30 km/h, 60 km/h, y parado al final hasta que se apague el GPS.';

  @override
  String get simular => 'Simular recorrido';

  @override
  String get detenerSimulacion => 'Detener simulación';

  @override
  String simulando(int i, int n) {
    return 'Simulando: segundo $i de $n';
  }

  @override
  String get simulacionIos =>
      'En el simulador de iOS la ruta se inyecta desde la Mac:';

  @override
  String get avisoTitulo => 'Registrando tu recorrido';

  @override
  String get avisoCuerpo => 'Se apaga solo cuando te detienes.';
}
