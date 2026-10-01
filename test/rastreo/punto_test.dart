import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/src/rastreo/canonico.dart';
import 'package:hz_collection_sdk/src/rastreo/detector_de_movimiento.dart';
import 'package:hz_collection_sdk/src/rastreo/punto.dart';

/// Contrato §4.12: lo que el sistema no da va con un centinela numérico, nunca `null` y
/// nunca 0 (0 es batería muerta, el norte y el nivel del mar).
PuntoDeRastreo _p({double h = 90, double alt = 900, int bat = 80}) => PuntoDeRastreo(
    t: 1727700000000, lat: 10.5, lon: -66.88, acc: 5, v: 3, h: h, alt: alt, mock: false,
    bat: bat);

void main() {
  group('valores desconocidos (§4.12)', () {
    test('batería desconocida → -1, no 0', () {
      expect(_p(bat: -1).bat, -1);
      expect(_p(bat: -100).bat, -1, reason: 'Transistor da -1 × 100');
      expect(_p(bat: 250).bat, -1, reason: 'fuera de rango no se recorta a 100');
      expect(_p(bat: 0).bat, 0, reason: 'batería muerta de verdad sigue siendo 0');
      expect(_p(bat: 100).bat, 100);
    });

    test('rumbo desconocido → -1, no 0; el norte sigue siendo 0', () {
      expect(_p(h: -1).h, -1);
      expect(_p(h: -37).h, -1, reason: 'iOS da course < 0 cuando no lo sabe');
      expect(_p(h: double.nan).h, -1);
      expect(_p(h: 0).h, 0);
      expect(_p(h: 360).h, 0);
      expect(_p(h: 359.94).h, 359.9);
    });

    test('altitud desconocida → -9999, no 0; bajo el nivel del mar se respeta', () {
      expect(_p(alt: -9999).alt, -9999);
      expect(_p(alt: double.nan).alt, -9999);
      expect(_p(alt: double.negativeInfinity).alt, -9999);
      expect(_p(alt: -20000).alt, -9999);
      expect(_p(alt: 0).alt, 0);
      expect(_p(alt: -28.04).alt, -28, reason: 'el Mar Muerto de verdad no es desconocido');
    });

    test('una Lectura sin rumbo ni altitud trae los centinelas por omisión', () {
      const l = Lectura(t: 1, lat: 1, lon: 1, acc: 1, v: 1);
      expect(l.h, PuntoDeRastreo.rumboDesconocido);
      expect(l.alt, PuntoDeRastreo.altitudDesconocida);
    });

    test('siguen siendo numéricos en el JSON, nunca null, y canónicos como JS', () {
      final p = _p(h: -1, alt: -9999, bat: -1);
      final j = p.toJson();
      expect(j.values.where((v) => v == null), isEmpty);
      expect(j['h'], isA<num>());
      expect(j['alt'], isA<num>());
      expect(j['bat'], isA<int>());
      // JSON.stringify(-1) y JSON.stringify(-9999) en JS: sin «.0».
      expect(jsonCanonico(j),
          '{"acc":5,"alt":-9999,"bat":-1,"h":-1,"lat":10.5,"lon":-66.88,"mock":false,'
          '"t":1727700000000,"v":3}');
      // Ida y vuelta por la cola: el centinela sobrevive.
      final r = PuntoDeRastreo.fromJson(j);
      expect((r.h, r.alt, r.bat), (-1.0, -9999.0, -1));
    });
  });

  group('bordes que el servidor rechaza', () {
    PuntoDeRastreo mk({double h = 10, double alt = 5}) => PuntoDeRastreo(
        t: 1727700000000, lat: 10.5, lon: -66.88, acc: 5, v: 3, h: h, alt: alt, mock: false, bat: 50);
    test('rumbo 359,96 no redondea a 360', () {
      expect(mk(h: 359.96).h, lessThan(360));
      expect(mk(h: 359.96).h, greaterThanOrEqualTo(0));
    });
    test('altitud fuera de [-500, 10000] va como desconocida', () {
      expect(mk(alt: -1200).alt, -9999);
      expect(mk(alt: 12000).alt, -9999);
      expect(mk(alt: -500).alt, -500);
    });
  });
}
