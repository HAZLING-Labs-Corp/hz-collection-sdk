import 'package:hz_collection_sdk/src/remote_config.dart' show ConfigStore;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El acuse de un aviso que llegó con la aplicación cerrada. Ver H-09.
///
/// El manejador de segundo plano corre en **otro isolate**: no ve nada de lo
/// que dejó `init()` en memoria. Lo único que cruza es `SharedPreferences`, así
/// que la llave y la URL tienen que estar ahí o el acuse no sale — y como el
/// caso normal de una notificación es llegar con la app cerrada, no sacarlo
/// significa que la consola muestre «aceptado» sobre avisos que sí llegaron.
void main() {
  group('la credencial que cruza al isolate', () {
    test('lo guardado se puede volver a leer', () async {
      SharedPreferences.setMockInitialValues({});
      final almacen = ConfigStore();

      await almacen.guardarCredencial('pk_live_abc.def', 'https://push.test');
      final leida = await almacen.leerCredencial();

      expect(leida?.llave, 'pk_live_abc.def');
      expect(leida?.url, 'https://push.test');
    });

    test('sin nada guardado devuelve nulo, no explota', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await ConfigStore().leerCredencial(), isNull);
    });

    test('un contenido corrupto devuelve nulo, no explota', () async {
      // Si esto tirara una excepción, se la comería el `catch` del manejador y
      // el acuse se perdería en silencio. Devolver nulo es lo mismo de cara al
      // resultado, pero deja el motivo a la vista de quien lea el código.
      SharedPreferences.setMockInitialValues(
          {'akpush.credencial': 'esto no es json'});
      expect(await ConfigStore().leerCredencial(), isNull);
    });

    test('a medias —sin url— devuelve nulo', () async {
      SharedPreferences.setMockInitialValues(
          {'akpush.credencial': '{"llave":"pk_live_abc.def"}'});
      expect(await ConfigStore().leerCredencial(), isNull);
    });

    test('cerrar sesión NO se lleva la credencial', () async {
      // Es del teléfono, no de la persona. El aparato sigue recibiendo avisos
      // después de cerrar sesión, y esos avisos también tienen que acusar
      // recibo: si la credencial se fuera con la sesión, el primer aviso
      // después de un cierre de sesión dejaría de contarse.
      SharedPreferences.setMockInitialValues({});
      final almacen = ConfigStore();
      await almacen.guardarCredencial('pk_live_abc.def', 'https://push.test');

      await almacen.olvidarSesion();

      expect((await almacen.leerCredencial())?.llave, 'pk_live_abc.def');
    });
  });
}
