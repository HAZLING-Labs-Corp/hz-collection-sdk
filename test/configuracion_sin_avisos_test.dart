import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:hz_collection_sdk/src/rastreo/api_de_rastreo.dart';

/// 🔴 «SE PUEDE MEDIR SIN PODER AVISAR» (01-10-2026): Collection contesta 200 con
/// `puede_avisar: false` y SIN bloque `firebase` cuando al paquete le faltan las llaves de
/// envío. Antes `AkPushConfig.fromJson` reventaba con un TypeError y `init()` se caía entero.
void main() {
  group('la configuración sin Firebase', () {
    /// La forma EXACTA medida el 01-10 con `com.estela.asegurado.dev` en `estela_prueba`.
    const sinFirebase = {
      'ok': true,
      'comercio': 'estela_prueba',
      'version': 1,
      'puede_avisar': false,
      'falta_para_avisar': ['la clave de la app', 'el identificador del remitente'],
      'politica': {'momento': 'arranque', 'obligatorio': false, 'preguntaBlanda': false, 'reintentarCadaDias': 7, 'textos': {}},
    };

    test('es un appMismatch (sin avisos), no un TypeError', () {
      expect(
        () => AkPushConfig.fromJson(Map<String, dynamic>.from(sinFirebase)),
        throwsA(isA<AkPushError>()
            .having((e) => e.code, 'code', AkPushErrorCode.appMismatch)
            .having((e) => e.details, 'details', contains('la clave de la app'))),
      );
    });

    test('sin bloque y sin la lista de lo que falta, también se dice', () {
      expect(
        () => AkPushConfig.fromJson({'ok': true, 'version': 1}),
        throwsA(isA<AkPushError>().having((e) => e.code, 'code', AkPushErrorCode.appMismatch)),
      );
    });

    test('con el bloque firebase completo sigue leyéndose igual', () {
      final c = AkPushConfig.fromJson({
        ...sinFirebase,
        'puede_avisar': true,
        'firebase': {'projectId': 'p', 'appId': '1:2:android:3', 'apiKey': 'k', 'messagingSenderId': '2'},
      });
      expect(c.projectId, 'p');
      expect(c.version, '1');
    });
  });

  group('la versión del texto del rastreo', () {
    test('sin el campo es 1, lo que el SDK mandaba siempre', () {
      expect(ConfiguracionDeRastreo.fromJson({'activo': true}).versionDelTexto, 1);
      expect(ConfiguracionDeRastreo.apagada.versionDelTexto, 1);
    });

    test('se lee, se acota a 1 como piso y sobrevive al guardado', () {
      final c = ConfiguracionDeRastreo.fromJson({'activo': true, 'versionDelTexto': 3});
      expect(c.versionDelTexto, 3);
      expect(ConfiguracionDeRastreo.fromJson(c.toJson()).versionDelTexto, 3);
      expect(ConfiguracionDeRastreo.fromJson({'versionDelTexto': 0}).versionDelTexto, 1);
    });

    test('la API pone la versión del comercio en el bloque, y la del bloque manda si viene', () async {
      var cuerpo = '{"version":4,"rastreo":{"activo":true}}';
      final api = ApiDeRastreo(llave: 'pk_prueba', url: 'http://api', cliente: MockClient((_) async => http.Response(cuerpo, 200)));
      final (bloque, _) = await api.leerConfiguracion('com.app');
      expect(ConfiguracionDeRastreo.fromJson(bloque).versionDelTexto, 4);
      cuerpo = '{"version":4,"rastreo":{"activo":true,"versionDelTexto":7}}';
      final (otro, _) = await api.leerConfiguracion('com.app');
      expect(ConfiguracionDeRastreo.fromJson(otro).versionDelTexto, 7);
    });
  });
}
