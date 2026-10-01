/// LAS ETIQUETAS BLE — qué escuchar (bloque `rastreo.etiquetas` de /configuracion) y cómo se
/// reconoce un anuncio (01-10-2026).
///
/// ```
/// etiquetas: { lista: [ { etiquetaId, tipo: ibeacon|eddystone-uid|altbeacon, uuid, major, minor
///                         | namespace, instance } ], escaneoSeg: 8, cadaSeg: 30, rssiMin: -95 }
/// ```
///
/// El aparato SÓLO INFORMA lo que oyó (`{t, etiquetaId, rssi}` dentro del lote firmado); si la
/// etiqueta estuvo «cerca» lo decide el servidor. Si el bloque no viene, no se escanea.
library;

import 'dart:typed_data';

class EtiquetaBle {
  const EtiquetaBle({
    required this.etiquetaId,
    required this.tipo,
    this.uuid,
    this.major,
    this.minor,
    this.namespace,
    this.instance,
  });

  final String etiquetaId;

  /// `ibeacon`, `eddystone-uid` o `altbeacon`.
  final String tipo;

  /// iBeacon / AltBeacon: el UUID en minúsculas con guiones, y major/minor.
  final String? uuid;
  final int? major;
  final int? minor;

  /// Eddystone-UID: 20 y 12 caracteres hex, minúsculas.
  final String? namespace;
  final String? instance;

  static const tipos = {'ibeacon', 'eddystone-uid', 'altbeacon'};
  static final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  static final _id = RegExp(r'^[A-Za-z0-9._:-]{1,64}$');

  /// `null` si la entrada no se entiende: una etiqueta mal escrita no se escucha (nunca rompe la config).
  static EtiquetaBle? fromJson(Object? crudo) {
    if (crudo is! Map) return null;
    final id = crudo['etiquetaId'], tipo = crudo['tipo'];
    if (id is! String || !_id.hasMatch(id) || tipo is! String || !tipos.contains(tipo)) return null;
    if (tipo == 'eddystone-uid') {
      final ns = crudo['namespace'], ins = crudo['instance'];
      if (ns is! String || !RegExp(r'^[0-9a-f]{20}$').hasMatch(ns)) return null;
      if (ins is! String || !RegExp(r'^[0-9a-f]{12}$').hasMatch(ins)) return null;
      return EtiquetaBle(etiquetaId: id, tipo: tipo, namespace: ns, instance: ins);
    }
    final u = crudo['uuid'], ma = crudo['major'], mi = crudo['minor'];
    bool u16(Object? x) => x is int && x >= 0 && x <= 65535;
    if (u is! String || !_uuid.hasMatch(u.toLowerCase()) || !u16(ma) || !u16(mi)) return null;
    return EtiquetaBle(etiquetaId: id, tipo: tipo, uuid: u.toLowerCase(), major: ma as int, minor: mi as int);
  }

  Map<String, dynamic> toJson() => {
        'etiquetaId': etiquetaId,
        'tipo': tipo,
        if (uuid != null) ...{'uuid': uuid, 'major': major, 'minor': minor},
        if (namespace != null) ...{'namespace': namespace, 'instance': instance},
      };
}

class ConfiguracionDeEtiquetas {
  const ConfiguracionDeEtiquetas({
    this.lista = const [],
    this.escaneoSeg = 8,
    this.cadaSeg = 30,
    this.rssiMin = -95,
  });

  final List<EtiquetaBle> lista;

  /// Duración de cada ventana de escaneo (2..60 s).
  final int escaneoSeg;

  /// Cada cuánto se abre una ventana MIENTRAS RUEDA (escaneoSeg..600 s). Detenido no se escanea.
  final int cadaSeg;

  /// Por debajo de esto no se informa (dBm).
  final int rssiMin;

  static const ninguna = ConfiguracionDeEtiquetas();

  bool get hayQueEscuchar => lista.isNotEmpty;

  /// Lo que falta o no se entiende cae hacia abajo: sin lista, no se escanea; números acotados
  /// (un `cadaSeg: 0` sería escaneo continuo, y eso es batería).
  factory ConfiguracionDeEtiquetas.fromJson(Object? crudo) {
    if (crudo is! Map) return ninguna;
    int n(String k, int siNo, int piso, int techo) {
      final v = crudo[k];
      return (v is num && v.isFinite ? v.round() : siNo).clamp(piso, techo);
    }

    final l = crudo['lista'];
    final lista = <EtiquetaBle>[
      if (l is List) ...l.take(10).map(EtiquetaBle.fromJson).whereType<EtiquetaBle>(),
    ];
    final escaneo = n('escaneoSeg', 8, 2, 60);
    return ConfiguracionDeEtiquetas(
      lista: lista,
      escaneoSeg: escaneo,
      cadaSeg: n('cadaSeg', 30, escaneo < 10 ? 10 : escaneo, 600),
      rssiMin: n('rssiMin', -95, -127, -30),
    );
  }

  Map<String, dynamic> toJson() => {
        'lista': [for (final e in lista) e.toJson()],
        'escaneoSeg': escaneoSeg,
        'cadaSeg': cadaSeg,
        'rssiMin': rssiMin,
      };
}

/// Lo que se le informa al servidor: cuándo, qué etiqueta y con cuánta señal.
class Avistamiento {
  const Avistamiento({required this.t, required this.etiquetaId, required this.rssi});
  final int t;
  final String etiquetaId;
  final int rssi;
  Map<String, dynamic> toJson() => {'t': t, 'etiquetaId': etiquetaId, 'rssi': rssi};
}

/// Un anuncio BLE crudo, tal como lo da cualquier escáner: el dato de fabricante (con los 2
/// bytes del fabricante adelante, little-endian, como lo da Android) y el dato de servicio por
/// UUID de 16 bits en minúsculas (`feaa` para Eddystone).
class AnuncioBle {
  const AnuncioBle({required this.rssi, this.fabricante, this.servicios = const {}});
  final int rssi;
  final Uint8List? fabricante;
  final Map<String, Uint8List> servicios;
}

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
String _uuidDe(List<int> b) {
  final h = _hex(b);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Los identificadores que trae un anuncio, en la forma de la huella del servidor
/// (`uuid|<uuid>|major|minor` o `eddystone-uid|<ns>|<inst>`), o `null` si no es una etiqueta.
String? identificadorDelAnuncio(AnuncioBle a) {
  final f = a.fabricante;
  if (f != null && f.length >= 2 + 22) {
    final empresa = f[0] | (f[1] << 8);
    // iBeacon: Apple (0x004C), tipo 0x02, largo 0x15, uuid 16, major 2, minor 2 (big-endian), tx
    if (empresa == 0x004c && f[2] == 0x02 && f[3] == 0x15 && f.length >= 25) {
      return 'uuid|${_uuidDe(f.sublist(4, 20))}|${(f[20] << 8) | f[21]}|${(f[22] << 8) | f[23]}';
    }
    // AltBeacon: cualquier fabricante, código 0xBEAC, id1 16, id2 2, id3 2, tx, reservado
    if (f[2] == 0xbe && f[3] == 0xac && f.length >= 26) {
      return 'uuid|${_uuidDe(f.sublist(4, 20))}|${(f[20] << 8) | f[21]}|${(f[22] << 8) | f[23]}';
    }
  }
  // Eddystone-UID: dato de servicio de 0xFEAA, marco 0x00, tx, namespace 10, instance 6
  final e = a.servicios['feaa'];
  if (e != null && e.length >= 18 && e[0] == 0x00) {
    return 'eddystone-uid|${_hex(e.sublist(2, 12))}|${_hex(e.sublist(12, 18))}';
  }
  return null;
}

/// La huella de una etiqueta configurada (la misma forma que [identificadorDelAnuncio]).
String identificadorDe(EtiquetaBle e) =>
    e.tipo == 'eddystone-uid' ? 'eddystone-uid|${e.namespace}|${e.instance}' : 'uuid|${e.uuid}|${e.major}|${e.minor}';
