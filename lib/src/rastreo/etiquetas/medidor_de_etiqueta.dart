/// EL MEDIDOR DE LA ETIQUETA — la señal de UNA etiqueta en vivo, para una pantalla que la
/// muestra mientras está abierta (01-10-2026).
///
/// Escucha continuo y en baja latencia, así que gasta: se usa sólo con la pantalla abierta y se
/// cancela al salir. No informa nada a ningún servidor. Qué tan «cerca» es, lo decide quien mira.
library;

import 'escaner_ble.dart';
import 'etiquetas_ble.dart';

/// Una vez que se oyó la etiqueta: cuándo y con cuánta señal (dBm).
class LecturaDeSenal {
  const LecturaDeSenal({required this.rssi, required this.t});
  final int rssi;
  final DateTime t;
}

class MedidorDeEtiqueta {
  MedidorDeEtiqueta({EscanerBle? escaner}) : _escaner = escaner ?? EscanerReactivo();
  final EscanerBle _escaner;

  /// Cada anuncio de [etiqueta] que se oye, mientras dure la suscripción. Si el Bluetooth falla,
  /// el error sale por el flujo.
  Stream<LecturaDeSenal> medir(EtiquetaBle etiqueta) {
    final huella = identificadorDe(etiqueta);
    return _escaner
        .escuchar(rapido: true)
        .where((a) => identificadorDelAnuncio(a) == huella)
        .map((a) => LecturaDeSenal(rssi: a.rssi, t: DateTime.now()));
  }
}
