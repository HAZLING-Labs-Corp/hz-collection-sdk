/// EL LOTE FIRMADO — PM-025 §4.1, campo por campo.
///
/// ```
/// { instalacionId, loteId (uuid), claveId, alg: "ES256", hashAnterior, hash, firma,
///   reloj: { mono, arranques, gnss },
///   puntos: [ { t, lat, lon, acc, v, h, alt, mock, bat } ], medio? }
/// ```
///
/// `hash` = SHA-256 (hex) del JSON canónico del cuerpo SIN `hash` ni `firma`.
/// `firma` = ES256 (ECDSA P-256 + SHA-256) de los MISMOS bytes canónicos, en base64 de la
/// firma DER. `hashAnterior` = el `hash` del lote anterior que la ingesta aceptó, o `"0"`.
///
/// ══ 🔴 SE ARMA UNA VEZ Y SE MANDA IGUAL SIEMPRE ══
///
/// El lote se arma, se firma y se guarda en la cola **antes** de mandarlo. Un reintento
/// manda los mismos bytes con el mismo `loteId`: la ingesta lo reconoce (200) y no duplica.
/// Volver a armarlo en cada intento cambiaría la firma (ECDSA usa un azar distinto cada
/// vez) y, si alguien cambiara el orden de un campo, también el hash.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'canonico.dart';
import 'medidor_de_hilo.dart';
import 'etiquetas/etiquetas_ble.dart';
import 'punto.dart';

/// Los dos relojes del aparato además del de la pared (PM-024 §11.6).
class RelojDelLote {
  const RelojDelLote({required this.mono, required this.arranques, this.gnss});

  /// Milisegundos desde que arrancó el aparato, contando el tiempo dormido. No lo mueve
  /// nadie cambiando la hora del teléfono.
  final int mono;

  /// Cuántas veces arrancó el aparato. Si `mono` retrocede sin que esto suba, algo raro
  /// pasó con el reloj.
  final int arranques;

  /// La hora del GNSS de la última fijación del lote (ms desde época), o `null`.
  final int? gnss;

  Map<String, dynamic> toJson() => {'mono': mono, 'arranques': arranques, 'gnss': gnss};
}

/// Quien firma. En el teléfono es la clave del Keystore / Secure Enclave; en una prueba,
/// cualquier cosa que devuelva una firma.
abstract class FirmadorDeLotes {
  /// La huella de la pública: SHA-256 hex del SPKI DER.
  String get claveId;

  /// Firma ES256 de [bytes] (el SDK nunca le pasa el hash: ES256 hashea adentro).
  /// Devuelve la firma DER en base64.
  Future<String> firmar(List<int> bytes);
}

/// Un lote listo para mandar: los bytes exactos que van a salir, y lo que hace falta
/// saber de él sin volver a leerlos.
class LoteArmado {
  const LoteArmado({
    required this.loteId,
    required this.hash,
    required this.hashAnterior,
    required this.cuerpo,
    required this.n,
    required this.medidoMin,
    required this.medidoMax,
  });

  final String loteId;
  final String hash;
  final String hashAnterior;

  /// El cuerpo completo, canónico, con `hash` y `firma`. Es literalmente lo que sale.
  final String cuerpo;
  final int n;
  final int medidoMin;
  final int medidoMax;

  int get bytes => utf8.encode(cuerpo).length;
}

/// El cuerpo sin `hash` ni `firma`, como mapa. Separado para poder probarlo.
Map<String, dynamic> cuerpoSinFirmar({
  required String instalacionId,
  required String loteId,
  required String claveId,
  required String hashAnterior,
  required RelojDelLote reloj,
  required List<PuntoDeRastreo> puntos,
  String? medio,
  List<Avistamiento> avistamientos = const [],
}) =>
    {
      'instalacionId': instalacionId,
      'loteId': loteId,
      'claveId': claveId,
      'alg': 'ES256',
      'hashAnterior': hashAnterior,
      'reloj': reloj.toJson(),
      'puntos': [for (final p in puntos) p.toJson()],
      // tramo 3.2 (opcional): el medio declarado para el viaje. Entra al hash como cualquier
      // campo; sin declarar, la clave NO va (un lote viejo sigue siendo byte a byte el mismo).
      if (medio != null) 'medio': medio,
      // etiquetas BLE (opcional): lo que se oyó; sin nada oído la clave NO va (mismo criterio)
      if (avistamientos.isNotEmpty) 'avistamientos': [for (final a in avistamientos) a.toJson()],
    };

Future<LoteArmado> armarLote({
  required String instalacionId,
  required String loteId,
  required String hashAnterior,
  required RelojDelLote reloj,
  required List<PuntoDeRastreo> puntos,
  required FirmadorDeLotes firmador,
  String? medio,
  List<Avistamiento> avistamientos = const [],
}) async {
  if (puntos.isEmpty) {
    throw ArgumentError('Un lote sin puntos no se arma: no prueba nada y gasta un request.');
  }
  // Lo de Dart va de corrido en el hilo principal (hilos fusionados): se mide como bloqueo.
  // Medido en el emulador con 40 puntos: ver RESUMEN-A2 §4. La firma es nativa y va en un
  // hilo propio (RastreoNativo.kt / .swift): acá sólo se espera.
  final (sinFirmar, canonico, hash) = MedidorDeHilo.sincrono('lote.canonico+sha256(${puntos.length})', () {
    final m = cuerpoSinFirmar(
      instalacionId: instalacionId,
      loteId: loteId,
      claveId: firmador.claveId,
      hashAnterior: hashAnterior,
      reloj: reloj,
      puntos: puntos,
      medio: medio,
      avistamientos: avistamientos,
    );
    final c = jsonCanonico(m);
    return (m, c, sha256Hex(c));
  });
  final firma = await MedidorDeHilo.asincrono(
      'lote.firmar(nativo)', () => firmador.firmar(utf8.encode(canonico)));
  final cuerpo = MedidorDeHilo.sincrono(
      'lote.cuerpoFinal', () => jsonCanonico({...sinFirmar, 'hash': hash, 'firma': firma}));
  var min = puntos.first.t, max = puntos.first.t;
  for (final p in puntos) {
    if (p.t < min) min = p.t;
    if (p.t > max) max = p.t;
  }
  return LoteArmado(
    loteId: loteId,
    hash: hash,
    hashAnterior: hashAnterior,
    cuerpo: cuerpo,
    n: puntos.length,
    medidoMin: min,
    medidoMax: max,
  );
}

/// Un UUID v4 con `Random.secure()`, igual que `ConfigStore._generarInstalacionId`.
String nuevoUuid() {
  final azar = math.Random.secure();
  final b = List<int>.generate(16, (_) => azar.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int d, int h) =>
      b.sublist(d, h).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
