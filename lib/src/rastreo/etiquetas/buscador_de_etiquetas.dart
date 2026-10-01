/// BUSCAR LA ETIQUETA QUE ESTÁ AL LADO — para vincularla sin escribir números (01-10-2026).
///
/// La persona acerca el teléfono a la etiqueta; se escucha [duracion] partida en dos mitades y
/// sólo queda lo que se oyó EN LAS DOS (una etiqueta que pasó una vez, la del vecino en la
/// esquina, no cuenta) y con señal media por encima de [rssiMin] (≈ a menos de un metro). La más
/// fuerte va primero; quien llama le pregunta a la persona «¿es esta?» antes de registrarla.
///
/// No informa nada a ningún servidor: sólo devuelve lo que oyó. Registrar es de la app.
library;

import 'dart:async';

import 'escaner_ble.dart';
import 'etiquetas_ble.dart';

/// Una etiqueta oída durante la búsqueda, con los datos que pide el alta.
class EtiquetaCercana {
  const EtiquetaCercana({
    required this.tipo,
    required this.identificador,
    required this.rssiMedio,
    required this.rssiMax,
    required this.veces,
    this.uuid,
    this.major,
    this.minor,
    this.namespace,
    this.instance,
  });

  /// `ibeacon`, `altbeacon` o `eddystone-uid`.
  final String tipo;

  /// La huella, en la misma forma que la del servidor.
  final String identificador;
  final int rssiMedio;
  final int rssiMax;
  final int veces;
  final String? uuid;
  final int? major;
  final int? minor;
  final String? namespace;
  final String? instance;

  /// El cuerpo del alta (`tipo, uuid, major, minor | namespace, instance`).
  Map<String, dynamic> toJson() => {
        'tipo': tipo,
        if (uuid != null) ...{'uuid': uuid, 'major': major, 'minor': minor},
        if (namespace != null) ...{'namespace': namespace, 'instance': instance},
      };
}

/// `ibeacon` | `altbeacon` | `eddystone-uid`, o `null` si el anuncio no es una etiqueta.
String? tipoDelAnuncio(AnuncioBle a) {
  final f = a.fabricante;
  if (f != null && f.length >= 25) {
    if ((f[0] | (f[1] << 8)) == 0x004c && f[2] == 0x02 && f[3] == 0x15) return 'ibeacon';
    if (f[2] == 0xbe && f[3] == 0xac && f.length >= 26) return 'altbeacon';
  }
  final e = a.servicios['feaa'];
  if (e != null && e.length >= 18 && e[0] == 0x00) return 'eddystone-uid';
  return null;
}

class BuscadorDeEtiquetas {
  BuscadorDeEtiquetas({EscanerBle? escaner}) : _escaner = escaner ?? EscanerReactivo();
  final EscanerBle _escaner;

  /// Escucha [duracion] y devuelve las etiquetas cercanas, la más fuerte primero (puede ser
  /// vacía). Si el Bluetooth está apagado o falta el permiso, el error sale tal cual.
  Future<List<EtiquetaCercana>> buscar({
    Duration duracion = const Duration(seconds: 10),
    int rssiMin = -70,
  }) async {
    final oidos = <String, _Oido>{};
    final inicio = DateTime.now();
    final mitad = duracion ~/ 2;
    final listo = Completer<void>();
    late final StreamSubscription<AnuncioBle> sub;
    sub = _escaner.escuchar(rapido: true).listen(
      (a) {
        final id = identificadorDelAnuncio(a), tipo = tipoDelAnuncio(a);
        if (id == null || tipo == null) return;
        final segunda = DateTime.now().difference(inicio) >= mitad;
        (oidos[id] ??= _Oido(tipo, id)).anotar(a.rssi, segunda);
      },
      onError: (Object e, StackTrace s) {
        if (!listo.isCompleted) listo.completeError(e, s);
      },
      onDone: () {
        if (!listo.isCompleted) listo.complete();
      },
    );
    final reloj = Timer(duracion, () {
      if (!listo.isCompleted) listo.complete();
    });
    try {
      await listo.future;
    } finally {
      reloj.cancel();
      await sub.cancel();
    }
    final cercanas = [
      for (final o in oidos.values)
        if (o.enLasDos && o.medio >= rssiMin) o.comoCercana(),
    ]..sort((a, b) => b.rssiMedio.compareTo(a.rssiMedio));
    return cercanas;
  }
}

class _Oido {
  _Oido(this.tipo, this.id);
  final String tipo, id;
  bool primera = false, segunda = false;
  int suma = 0, veces = 0, max = -127;

  void anotar(int rssi, bool enLaSegunda) {
    enLaSegunda ? segunda = true : primera = true;
    suma += rssi;
    veces++;
    if (rssi > max) max = rssi;
  }

  bool get enLasDos => primera && segunda;
  int get medio => (suma / veces).round();

  EtiquetaCercana comoCercana() {
    final p = id.split('|');
    return tipo == 'eddystone-uid'
        ? EtiquetaCercana(tipo: tipo, identificador: id, rssiMedio: medio, rssiMax: max, veces: veces, namespace: p[1], instance: p[2])
        : EtiquetaCercana(
            tipo: tipo, identificador: id, rssiMedio: medio, rssiMax: max, veces: veces,
            uuid: p[1], major: int.parse(p[2]), minor: int.parse(p[3]));
  }
}
