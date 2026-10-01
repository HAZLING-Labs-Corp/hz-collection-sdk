import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/hz_collection_sdk.dart';

const uuid = 'e2c56db5-dffb-48d2-b060-d0f5a71096e0';
List<int> _hex(String h) => [for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];
AnuncioBle ibeacon(int major, int minor, int rssi) => AnuncioBle(
      rssi: rssi,
      fabricante: Uint8List.fromList([0x4c, 0x00, 0x02, 0x15, ..._hex(uuid.replaceAll('-', '')), major >> 8, major & 0xff, minor >> 8, minor & 0xff, 0xc5]),
    );

/// Emite cada anuncio a los [ms] que se le diga desde que se abre la escucha.
class EscanerConReloj implements EscanerBle {
  EscanerConReloj(this.programa);
  final List<(int, AnuncioBle)> programa;
  @override
  Stream<AnuncioBle> escuchar({bool rapido = false}) {
    final c = StreamController<AnuncioBle>();
    for (final (ms, a) in programa) {
      Timer(Duration(milliseconds: ms), () {
        if (!c.isClosed) c.add(a);
      });
    }
    c.onCancel = c.close;
    return c.stream;
  }
}

void main() {
  test('la oída en las dos mitades y fuerte gana; la de una sola mitad o débil no cuenta', () async {
    final b = BuscadorDeEtiquetas(
      escaner: EscanerConReloj([
        (10, ibeacon(100, 7, -55)), (150, ibeacon(100, 7, -57)), // al lado, en las dos
        (20, ibeacon(200, 1, -50)), // fuerte pero sólo pasó una vez
        (30, ibeacon(300, 2, -85)), (160, ibeacon(300, 2, -86)), // en las dos, pero lejos
        (40, ibeacon(400, 3, -66)), (170, ibeacon(400, 3, -64)), // en las dos, más débil que la primera
      ]),
    );
    final r = await b.buscar(duracion: const Duration(milliseconds: 200), rssiMin: -70);
    expect(r.map((e) => e.minor), [7, 3]);
    expect(r.first.tipo, 'ibeacon');
    expect(r.first.rssiMedio, -56);
    expect(r.first.toJson(), {'tipo': 'ibeacon', 'uuid': uuid, 'major': 100, 'minor': 7});
  });

  test('sin nada cerca devuelve vacío', () async {
    final r = await BuscadorDeEtiquetas(escaner: EscanerConReloj([])).buscar(duracion: const Duration(milliseconds: 50));
    expect(r, isEmpty);
  });

  test('el medidor sólo entrega la etiqueta pedida, con su señal', () async {
    const mia = EtiquetaBle(etiquetaId: 'moto-1', tipo: 'ibeacon', uuid: uuid, major: 100, minor: 7);
    final m = MedidorDeEtiqueta(
      escaner: EscanerConReloj([(5, ibeacon(100, 7, -58)), (10, ibeacon(200, 1, -40)), (15, ibeacon(100, 7, -72))]),
    );
    final lecturas = await m.medir(mia).take(2).toList();
    expect(lecturas.map((l) => l.rssi), [-58, -72]);
  });

  test('si el Bluetooth falla, el error sale', () async {
    final b = BuscadorDeEtiquetas(escaner: _EscanerQueFalla());
    expect(b.buscar(duracion: const Duration(milliseconds: 50)), throwsA(isA<StateError>()));
  });
}

class _EscanerQueFalla implements EscanerBle {
  @override
  Stream<AnuncioBle> escuchar({bool rapido = false}) => Stream.error(StateError('bluetooth apagado'));
}
