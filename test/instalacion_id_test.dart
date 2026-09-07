import 'package:hz_collection_sdk/src/remote_config.dart' show ConfigStore;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El identificador de la INSTALACIÓN — el aparato, en el modelo nuevo.
///
/// 🔴 Nace la primera vez que se pide y tiene que sobrevivir el cierre de la
/// aplicación: si cada arranque generara uno distinto, el servidor vería una
/// instalación nueva cada vez y perdería el enlace con el sujeto que ya la
/// tenía asociada.
void main() {
  group('leerOCrearInstalacionId', () {
    test('la primera vez lo genera y lo persiste', () async {
      SharedPreferences.setMockInitialValues({});
      final almacen = ConfigStore();

      final id = await almacen.leerOCrearInstalacionId();

      expect(id, isNotEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('akpush.instalacionId'), id);
    });

    test('el mismo aparato mantiene el mismo id entre arranques', () async {
      // Dos `ConfigStore` distintos, como pasaría en dos arranques distintos
      // de la aplicación: lo que importa es que lean lo mismo del disco.
      SharedPreferences.setMockInitialValues({});
      final primero = await ConfigStore().leerOCrearInstalacionId();
      final segundo = await ConfigStore().leerOCrearInstalacionId();

      expect(segundo, primero);
    });

    test('dos aparatos sin nada guardado no coinciden', () async {
      SharedPreferences.setMockInitialValues({});
      final a = await ConfigStore().leerOCrearInstalacionId();

      SharedPreferences.setMockInitialValues({});
      final b = await ConfigStore().leerOCrearInstalacionId();

      expect(a, isNot(b));
    });

    test('tiene la forma de un UUID, para que el servidor lo pueda validar', () async {
      SharedPreferences.setMockInitialValues({});
      final id = await ConfigStore().leerOCrearInstalacionId();

      expect(
        id,
        matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        )),
      );
    });

    test('cerrar sesión NO se lleva la instalación', () async {
      // Es del aparato, no de la persona: sobrevive a `olvidarSesion()` igual
      // que la credencial — ver `acuse_en_segundo_plano_test.dart`.
      SharedPreferences.setMockInitialValues({});
      final almacen = ConfigStore();
      final id = await almacen.leerOCrearInstalacionId();

      await almacen.olvidarSesion();

      expect(await almacen.leerOCrearInstalacionId(), id);
    });
  });
}
