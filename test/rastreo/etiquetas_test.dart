import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/src/rastreo/canonico.dart';
import 'package:hz_collection_sdk/src/rastreo/configuracion_de_rastreo.dart';
import 'package:hz_collection_sdk/src/rastreo/etiquetas/escaner_ble.dart';
import 'package:hz_collection_sdk/src/rastreo/etiquetas/etiquetas_ble.dart';
import 'package:hz_collection_sdk/src/rastreo/etiquetas/vigia_de_etiquetas.dart';
import 'package:hz_collection_sdk/src/rastreo/lote.dart';
import 'package:hz_collection_sdk/src/rastreo/punto.dart';

const uuid = 'e2c56db5-dffb-48d2-b060-d0f5a71096e0';

List<int> _hex(String h) => [for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];

/// Un anuncio iBeacon como lo da Android: 4C 00 (Apple, little-endian) 02 15 uuid major minor tx.
AnuncioBle ibeacon(int major, int minor, int rssi) => AnuncioBle(
      rssi: rssi,
      fabricante: Uint8List.fromList([0x4c, 0x00, 0x02, 0x15, ..._hex(uuid.replaceAll('-', '')), major >> 8, major & 0xff, minor >> 8, minor & 0xff, 0xc5]),
    );

class EscanerFalso implements EscanerBle {
  final anuncios = <AnuncioBle>[];
  int aperturas = 0;
  bool fallar = false;
  StreamController<AnuncioBle>? abierto;

  @override
  Stream<AnuncioBle> escuchar({bool rapido = false}) {
    aperturas++;
    final c = StreamController<AnuncioBle>();
    abierto = c;
    if (fallar) {
      scheduleMicrotask(() => c.addError(StateError('Bluetooth apagado')));
    } else {
      scheduleMicrotask(() {
        for (final a in anuncios) {
          c.add(a);
        }
      });
    }
    return c.stream;
  }
}

final moto = EtiquetaBle.fromJson({'etiquetaId': 'moto', 'tipo': 'ibeacon', 'uuid': uuid, 'major': 100, 'minor': 7})!;

void main() {
  group('anuncios', () {
    test('iBeacon, AltBeacon y Eddystone-UID dan la huella del servidor', () {
      expect(identificadorDelAnuncio(ibeacon(100, 7, -60)), 'uuid|$uuid|100|7');
      final alt = AnuncioBle(rssi: -60, fabricante: Uint8List.fromList([0x18, 0x01, 0xbe, 0xac, ..._hex(uuid.replaceAll('-', '')), 0, 100, 0, 7, 0xc5, 0x00]));
      expect(identificadorDelAnuncio(alt), 'uuid|$uuid|100|7');
      final edd = AnuncioBle(rssi: -60, servicios: {'feaa': Uint8List.fromList([0x00, 0xee, ..._hex('edd1ebeac04e5defa017'), ..._hex('0bdb87539b67'), 0, 0])});
      expect(identificadorDelAnuncio(edd), 'eddystone-uid|edd1ebeac04e5defa017|0bdb87539b67');
      expect(identificadorDelAnuncio(AnuncioBle(rssi: -60, fabricante: Uint8List.fromList([1, 2, 3]))), isNull);
      expect(identificadorDe(moto), 'uuid|$uuid|100|7');
    });
  });

  group('configuración', () {
    test('sin bloque no se escucha; los números se acotan; una entrada mal escrita se ignora', () {
      expect(ConfiguracionDeRastreo.fromJson({'activo': true}).etiquetas.hayQueEscuchar, isFalse);
      final c = ConfiguracionDeEtiquetas.fromJson({
        'lista': [moto.toJson(), {'etiquetaId': 'x', 'tipo': 'ibeacon', 'uuid': 'no'}],
        'escaneoSeg': 0, 'cadaSeg': 0, 'rssiMin': -500,
      });
      expect(c.lista.map((e) => e.etiquetaId), ['moto']);
      expect(c.escaneoSeg, 2);
      expect(c.cadaSeg, 10, reason: 'escaneo continuo no: batería');
      expect(c.rssiMin, -127);
      final ida = ConfiguracionDeRastreo.fromJson({'activo': true, 'etiquetas': c.toJson()});
      expect(ConfiguracionDeRastreo.fromJson(ida.toJson()).etiquetas.lista.single.uuid, uuid, reason: 'sobrevive al disco');
    });
  });

  group('vigía', () {
    ConfiguracionDeEtiquetas conf() => ConfiguracionDeEtiquetas(lista: [moto], escaneoSeg: 8, cadaSeg: 30, rssiMin: -95);

    test('sólo escanea rodando y con etiquetas; una ventana corta deja el de más señal', () {
      fakeAsync((f) {
        final esc = EscanerFalso()..anuncios.addAll([ibeacon(100, 7, -80), ibeacon(100, 7, -66), ibeacon(100, 8, -40), ibeacon(100, 7, -99)]);
        var rodando = false;
        var c = conf();
        final v = VigiaDeEtiquetas(escaner: esc, configuracion: () => c, rodando: () => rodando, ahora: () => DateTime.fromMillisecondsSinceEpoch(1000));
        v.iniciar();
        f.elapse(const Duration(seconds: 65));
        expect(esc.aperturas, 0, reason: 'detenido no se escanea');
        rodando = true;
        f.elapse(const Duration(seconds: 30));
        expect(esc.aperturas, 1);
        expect(v.escuchando, isTrue);
        f.elapse(const Duration(seconds: 8));
        expect(v.escuchando, isFalse, reason: 'la ventana se corta sola');
        expect(v.pendientes, 1, reason: 'una por etiqueta y ventana; la ajena (minor 8) y la de -99 dBm no');
        final a = v.tomarHasta(5000).single;
        expect((a.etiquetaId, a.rssi), ('moto', -66));
        expect(v.pendientes, 0);
        c = ConfiguracionDeEtiquetas.ninguna;
        f.elapse(const Duration(seconds: 60));
        expect(esc.aperturas, 1, reason: 'sin etiquetas no se escanea');
        v.detener();
      });
    });

    test('Bluetooth apagado: se anota y se sigue', () {
      fakeAsync((f) {
        final problemas = <String>[];
        final esc = EscanerFalso()..fallar = true;
        final v = VigiaDeEtiquetas(escaner: esc, configuracion: conf, rodando: () => true, alProblema: problemas.add);
        v.iniciar();
        f.elapse(const Duration(seconds: 31));
        expect(problemas.single, contains('Bluetooth apagado'));
        expect(v.escuchando, isFalse);
        f.elapse(const Duration(seconds: 30));
        expect(esc.aperturas, 2, reason: 'reintenta en la ventana siguiente');
        v.detener();
      });
    });

    test('tomarHasta deja lo posterior para el lote siguiente', () {
      fakeAsync((f) {
        var ahora = 1000;
        final esc = EscanerFalso()..anuncios.add(ibeacon(100, 7, -70));
        final v = VigiaDeEtiquetas(escaner: esc, configuracion: conf, rodando: () => true, ahora: () => DateTime.fromMillisecondsSinceEpoch(ahora));
        v.ventana(conf());
        f.elapse(const Duration(seconds: 9));
        ahora = 50000;
        v.ventana(conf());
        f.elapse(const Duration(seconds: 9));
        expect(v.tomarHasta(10000).map((a) => a.t), [1000]);
        expect(v.tomarHasta(60000).map((a) => a.t), [50000]);
      });
    });
  });

  group('lote', () {
    test('los avistamientos entran al cuerpo firmado con los mismos bytes y hash que Node', () {
      final cuerpo = cuerpoSinFirmar(
        instalacionId: 'inst-1',
        loteId: '00000000-0000-4000-8000-000000000001',
        claveId: 'ab' * 32,
        hashAnterior: '0',
        reloj: const RelojDelLote(mono: 1, arranques: 1, gnss: 1727700000000),
        puntos: [PuntoDeRastreo(t: 1727700000000, lat: 10.5, lon: -66.88, acc: 5, v: 10, h: 0, alt: 900, mock: false, bat: 80)],
        avistamientos: const [Avistamiento(t: 1727700000500, etiquetaId: 'moto', rssi: -71)],
      );
      // vector calculado con `canonico` de la ingesta de Collection (dist/rastreo/ingesta/firma.js)
      expect(sha256Hex(jsonCanonico(cuerpo)), '099f4e8c8bacdafcd4d7c8a863d2cd56a39e95297b28dda2eab6f5a40b363efa');
    });
  });
}
