import 'package:hz_collection_sdk/src/device_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatosDelDispositivo', () {
    test('el desfase viaja siempre, aunque no se sepa nada más', () {
      // Lo mínimo que se puede saber de un teléfono. El desfase igual va: no
      // depende de ningún canal nativo, así que no tiene por qué faltar.
      const datos = DatosDelDispositivo(
        identificadorDePaquete: 'com.comercio.app',
        plataforma: 'android',
        desfaseUtcMinutos: -240,
      );

      expect(datos.toJson()['utcOffsetMinutes'], -240);
    });

    test('el huso y el idioma se omiten si no se supieron', () {
      const datos = DatosDelDispositivo(
        identificadorDePaquete: 'com.comercio.app',
        plataforma: 'android',
        desfaseUtcMinutos: 0,
      );

      final json = datos.toJson();
      // Ausente y presente-en-null no son lo mismo del otro lado: el servidor
      // guardaría un idioma que dice "null" y filtraría por él.
      expect(json.containsKey('timeZoneAbbreviation'), isFalse);
      expect(json.containsKey('locale'), isFalse);
      // Cero es un desfase real —Londres en invierno—, no un dato faltante.
      expect(json.containsKey('utcOffsetMinutes'), isTrue);
    });

    test('cuando se supieron, viajan con los nombres que espera el servicio',
        () {
      const datos = DatosDelDispositivo(
        identificadorDePaquete: 'com.comercio.app',
        plataforma: 'android',
        desfaseUtcMinutos: -240,
        zonaHorariaAbreviada: 'VET',
        idioma: 'es-VE',
      );

      expect(datos.toJson(), containsPair('timeZoneAbbreviation', 'VET'));
      expect(datos.toJson(), containsPair('locale', 'es-VE'));

      // 🔴 El nombre es parte del contrato. Lo que viaja NO es un identificador
      // IANA: mandarlo como `timeZone` invitaría al servidor a pasárselo a una
      // librería de husos, que con «VET» o «-04» no encuentra nada — y la hora
      // de envío volvería a calcularse contra la del servidor, que es el aviso
      // de cuota a las 3 de la mañana.
      expect(datos.toJson().containsKey('timeZone'), isFalse);
    });

    test('sin canal nativo no se inventa el identificador de paquete',
        () async {
      // Es preferible un 400 explicable a un identificador que no es el de esta
      // aplicación: con uno inventado el servidor entregaría la configuración
      // de otro comercio y el fallo aparecería mucho más lejos de su causa.
      TestWidgetsFlutterBinding.ensureInitialized();

      final datos = await DatosDelDispositivo.recolectar();
      expect(datos.identificadorDePaquete, isEmpty);
      expect(datos.plataforma, isNotEmpty);
    });

    test('la metadata que no se pudo leer no viaja en el alta', () async {
      // Perder el modelo del teléfono cuesta un dato de inventario; perder el
      // alta cuesta que esa persona no reciba nada. Por eso lo que no se supo
      // se omite —no viaja en null— y el alta sale igual.
      TestWidgetsFlutterBinding.ensureInitialized();

      final json = (await DatosDelDispositivo.recolectar()).toJson();

      for (final campo in [
        'deviceId',
        'model',
        'manufacturer',
        'brand',
        'osVersion',
        'isPhysicalDevice',
      ]) {
        expect(json.containsKey(campo), isFalse, reason: campo);
      }
      expect(json.values, isNot(contains(null)));
    });

    test('sin canales nativos el alta igual sale con hora e idioma', () async {
      // En la prueba no hay plugins registrados: es el mismo escenario que un
      // teléfono donde el canal nativo no contesta. Si esto rompe, se rompió la
      // degradación, y con ella el alta de esa persona.
      TestWidgetsFlutterBinding.ensureInitialized();

      final datos = await DatosDelDispositivo.recolectar();
      final json = datos.toJson();

      expect(json['utcOffsetMinutes'], DateTime.now().timeZoneOffset.inMinutes);
      // No se afirma un idioma concreto: depende de la máquina que corra la
      // prueba. Lo que sí tiene que ser cierto es que no se manda basura.
      final idioma = json['locale'] as String?;
      expect(idioma == null || idioma.isNotEmpty, isTrue);
      expect(idioma?.startsWith('und'), isNot(true));
    });
  });
}
