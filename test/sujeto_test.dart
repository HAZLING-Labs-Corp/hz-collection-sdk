import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

/// El sujeto — quien se loguea. Es la raíz del modelo nuevo, y estos son los
/// tipos con los que se arma: [TipoDeSujeto], [Documento] y [Organizacion].
///
/// No hay red ni disco de por medio: es sólo la ida y vuelta a JSON, que es lo
/// que viaja en `POST /api/v1/sujetos`.
void main() {
  group('TipoDeSujeto', () {
    test('un valor desconocido cae en natural, y no rompe', () {
      // Igual que `PoliticaDeNotificaciones._momentoDesde`: si el servicio
      // agrega un tipo nuevo mañana, una versión vieja del paquete tiene que
      // poder seguir leyendo en vez de fallar por una palabra que no conoce.
      expect(TipoDeSujeto.desde('lo-que-sea'), TipoDeSujeto.natural);
      expect(TipoDeSujeto.desde(null), TipoDeSujeto.natural);
      expect(TipoDeSujeto.desde('juridica'), TipoDeSujeto.juridica);
    });

    test('el valor que espera el servidor es el nombre tal cual', () {
      expect(TipoDeSujeto.natural.valor, 'natural');
      expect(TipoDeSujeto.juridica.valor, 'juridica');
    });
  });

  group('Documento', () {
    test('sobrevive a la ida y vuelta', () {
      const d = Documento(clase: ClaseDeDocumento.rif, numero: 'J-304521679');
      final vuelta = Documento.fromJson(d.toJson());
      expect(vuelta.clase, ClaseDeDocumento.rif);
      expect(vuelta.numero, 'J-304521679');
    });

    test('el número se guarda tal cual llega, sin normalizar', () {
      // Igual que hace el servidor: sacarle guiones acá sería inventarle al
      // comercio un número que no es el que tiene anotado.
      const d = Documento(clase: ClaseDeDocumento.cedula, numero: '0012137717');
      expect(Documento.fromJson(d.toJson()).numero, '0012137717');
    });

    test('una clase desconocida cae en cédula', () {
      final d = Documento.fromJson({'clase': 'algo-nuevo', 'numero': '1'});
      expect(d.clase, ClaseDeDocumento.cedula);
    });

    test('las cuatro clases viajan y vuelven sin cambiar', () {
      for (final clase in ClaseDeDocumento.values) {
        final d = Documento(clase: clase, numero: '1');
        expect(Documento.fromJson(d.toJson()).clase, clase, reason: clase.name);
      }
    });
  });

  group('Organizacion', () {
    test('el código es lo único obligatorio', () {
      const o = Organizacion(codigo: 'prov-01');
      final vuelta = Organizacion.fromJson(o.toJson());
      expect(vuelta.codigo, 'prov-01');
      expect(vuelta.nombre, isNull);
      expect(vuelta.rol, isNull);
    });

    test('sobrevive a la ida y vuelta completa', () {
      const o = Organizacion(
        codigo: 'prov-logisticasur',
        nombre: 'Logística Sur, C.A.',
        rol: 'repartidor',
      );
      final vuelta = Organizacion.fromJson(o.toJson());
      expect(vuelta.codigo, o.codigo);
      expect(vuelta.nombre, o.nombre);
      expect(vuelta.rol, o.rol);
    });

    test('nombre y rol ausentes no viajan como null explícito', () {
      // Un campo ausente y un campo con `null` son cosas distintas para quien
      // lo lee del otro lado — el mismo criterio que usa el resto del paquete.
      const o = Organizacion(codigo: 'prov-01');
      expect(o.toJson().containsKey('nombre'), isFalse);
      expect(o.toJson().containsKey('rol'), isFalse);
    });
  });
}
