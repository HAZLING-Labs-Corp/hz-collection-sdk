import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/src/rastreo/canonico.dart';
import 'package:hz_collection_sdk/src/rastreo/lote.dart';
import 'package:hz_collection_sdk/src/rastreo/punto.dart';

/// El JSON canónico tiene que dar LOS MISMOS BYTES que `JSON.stringify` con claves
/// ordenadas en la ingesta (TypeScript). El texto y el hash esperados de abajo salieron de
/// Node 20 el 2026-09-30 con el mismo cuerpo (ver RESUMEN-A.md): si esta prueba se rompe, la
/// ingesta rechaza todos los lotes con 401.
void main() {
  const esperadoTexto =
      '{"alg":"ES256","claveId":"abababababababababababababababababababababababababababababababab",'
      '"hashAnterior":"0","instalacionId":"inst-1","loteId":"00000000-0000-4000-8000-000000000001",'
      '"puntos":[{"acc":4.5,"alt":900.2,"bat":81,"h":90,"lat":10.4912837,"lon":-66.8791234,'
      '"mock":false,"t":1727700000000,"v":5},{"acc":0,"alt":-3,"bat":80,"h":359.9,"lat":10.5,'
      '"lon":-66.88,"mock":true,"t":1727700010000,"v":13.89}],'
      '"reloj":{"arranques":7,"gnss":1727700000000,"mono":123456789}}';
  const esperadoHash = '6e033537475b3ece21afe147eccb2c414bdfc0020ea7d2e08ebcf48622e2ea87';

  test('el cuerpo sin firmar da los mismos bytes y el mismo hash que Node', () {
    final cuerpo = cuerpoSinFirmar(
      instalacionId: 'inst-1',
      loteId: '00000000-0000-4000-8000-000000000001',
      claveId: 'ab' * 32,
      hashAnterior: '0',
      reloj: const RelojDelLote(mono: 123456789, arranques: 7, gnss: 1727700000000),
      puntos: [
        PuntoDeRastreo(
            t: 1727700000000, lat: 10.4912837, lon: -66.8791234, acc: 4.5, v: 5.0,
            h: 90.0, alt: 900.2, mock: false, bat: 81),
        PuntoDeRastreo(
            t: 1727700010000, lat: 10.5, lon: -66.88, acc: 0.0, v: 13.89,
            h: 359.9, alt: -3.0, mock: true, bat: 80),
      ],
    );
    final texto = jsonCanonico(cuerpo);
    expect(texto, esperadoTexto);
    expect(sha256Hex(texto), esperadoHash);
  });

  test('el vector de la ingesta (RESUMEN-B §8, RFC 8785) da su cadena y su hash', () {
    const texto =
        '{"alg":"ES256","claveId":"0000000000000000000000000000000000000000000000000000000000000000",'
        '"hashAnterior":"0","instalacionId":"inst-vector-0001","loteId":"00000000-0000-4000-8000-000000000001",'
        '"puntos":[{"acc":5,"alt":900.25,"bat":80,"h":0,"lat":10.5,"lon":-66.9,"mock":false,"t":1790000000000,"v":10},'
        '{"acc":4.5,"alt":901,"bat":79,"h":90,"lat":10.50012,"lon":-66.90011,"mock":false,"t":1790000007500,"v":8.33}],'
        '"reloj":{"arranques":2,"gnss":null,"mono":123456}}';
    // Los doubles en su origen: acc 5.0, v 10.0, h 0.0, alt 901.0 — lo que da Dart.
    final cuerpo = cuerpoSinFirmar(
      instalacionId: 'inst-vector-0001',
      loteId: '00000000-0000-4000-8000-000000000001',
      claveId: '0' * 64,
      hashAnterior: '0',
      reloj: const RelojDelLote(mono: 123456, arranques: 2, gnss: null),
      puntos: [
        PuntoDeRastreo(t: 1790000000000, lat: 10.5, lon: -66.9, acc: 5.0, v: 10.0, h: 0.0,
            alt: 900.25, mock: false, bat: 80),
        PuntoDeRastreo(t: 1790000007500, lat: 10.50012, lon: -66.90011, acc: 4.5, v: 8.33,
            h: 90.0, alt: 901.0, mock: false, bat: 79),
      ],
    );
    // El vector trae alt 900.25; el SDK redondea la altitud a la décima al GRABAR (ver
    // punto.dart), así que para probar el canónico solo se pone el double crudo.
    (cuerpo['puntos'] as List)[0]['alt'] = 900.25;
    final c = jsonCanonico(cuerpo);
    expect(c, texto);
    expect(sha256Hex(c), '8c45d3b13df82a5dacd486f4e7d8e238d797aec721d88e9f6f432e3a8ec1ea61');
  });

  test('los números se escriben como JavaScript', () {
    expect(numeroComoJavaScript(5.0), '5');
    expect(numeroComoJavaScript(-0.0), '0');
    expect(numeroComoJavaScript(1e-7), '1e-7');
    expect(numeroComoJavaScript(1.5e21), '1.5e+21');
    expect(numeroComoJavaScript(123.456), '123.456');
    expect(numeroComoJavaScript(0.1 + 0.2), '0.30000000000000004');
    expect(() => numeroComoJavaScript(double.nan), throwsArgumentError);
  });

  test('gnss nulo viaja como null, no se omite', () {
    expect(jsonCanonico(const RelojDelLote(mono: 1, arranques: 1).toJson()),
        '{"arranques":1,"gnss":null,"mono":1}');
  });

  test('el punto se redondea antes de guardarse', () {
    final p = PuntoDeRastreo(
        t: 1, lat: 10.491283746152837, lon: -66.87912341234, acc: 4.56, v: -1,
        h: 361.26, alt: 900.24, mock: false, bat: 130);
    expect(p.lat, 10.4912837);
    expect(p.lon, -66.8791234);
    expect(p.acc, 4.6);
    expect(p.v, 0); // sin velocidad no se inventa una negativa
    expect(p.h, 1.3);
    // Una batería fuera de 0-100 no es 100: es un dato roto → desconocida (§4.12).
    expect(p.bat, -1);
  });
}
