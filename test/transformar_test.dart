/// PRUEBAS DE LA CAPA DE TRANSFORMACIÓN.
///
/// 🔴 La que más importa es la última: que un campo que puede llevar texto escrito por una
/// persona NO pueda salir tal cual. Las demás comprueban el cálculo; ésa comprueba la regla,
/// y es la única que puede fallar por una decisión de alguien en vez de por un error.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/src/permisologia/transformar.dart';

void main() {
  group('la técnica de CredoLab, que es lo único que valía la pena copiar', () {
    test('un nombre se convierte en dos números y nunca sale como texto', () {
      const nombre = 'María Fernanda Solís';
      expect(transformar(nombre, Transformacion.palabras), 3);
      expect(transformar(nombre, Transformacion.largo), 20);
      // Y lo que importa: en ningún caso vuelve el texto.
      expect(transformar(nombre, Transformacion.palabras), isNot(contains('María')));
    });

    test('presencia descarta el contenido y deja «tiene o no tiene»', () {
      expect(transformar('Estoy de viaje', Transformacion.presencia), 1);
      expect(transformar('', Transformacion.presencia), 0);
      expect(transformar('   ', Transformacion.presencia), 0);
    });

    test('cuantos cuenta sin mirar qué hay adentro', () {
      expect(transformar([1, 2, 3], Transformacion.cuantos), 3);
      expect(transformar({'a': 1}, Transformacion.cuantos), 1);
      expect(transformar(const <int>[], Transformacion.cuantos), 0);
    });

    test('tramo redondea HACIA ABAJO', () {
      // «Más de 40» es una afirmación segura; «alrededor de 45» parece una precisión que no
      // hay, y en un puntaje esa diferencia se paga.
      expect(transformar(47, Transformacion.tramo), 40);
      expect(transformar(40, Transformacion.tramo), 40);
      expect(transformar(9, Transformacion.tramo), 0);
      expect(transformar(250, Transformacion.tramo, tramoDe: 100), 200);
    });
  });

  group('nulo no es cero', () {
    test('no medido devuelve nulo, no cero', () {
      // 🔴 Un cero dice «se midió y dio cero»; un nulo dice «no se midió». Confundirlos hace
      // que una estadística cuente como ceros a la gente de la que no se sabe nada.
      for (final t in Transformacion.values) {
        if (t == Transformacion.taICual) continue;
        expect(transformar(null, t), isNull, reason: '$t tiene que devolver nulo');
      }
    });

    test('y el paquete no incluye lo que no se midió', () {
      final p = armarPaquete(
        const [
          CampoRecolectado('nombre', Transformacion.palabras, queManda: 'cuántas palabras'),
          CampoRecolectado('nota', Transformacion.presencia, queManda: 'si tiene nota'),
        ],
        {'nombre': 'Ana Pérez'},
      );
      expect(p['nombre'], 2);
      expect(p.containsKey('nota'), isFalse,
          reason: 'mandar la clave con nulo hace creer que se midió y dio vacío');
    });
  });

  group('lo que hace que esto sea un muro y no una convención', () {
    test('el paquete recorre lo DECLARADO, no lo que trae la entrada', () {
      // El caso real: mañana alguien agrega una clave en el lugar de origen y nadie toca el
      // catálogo. Recorriendo la entrada, ese campo viajaría sin declarar y sin transformar.
      final p = armarPaquete(
        const [CampoRecolectado('modelo', Transformacion.taICual, queManda: 'el modelo')],
        {'modelo': 'Pixel 7', 'contactosTotales': 431, 'nombreDelDueno': 'Ana'},
      );
      expect(p.keys, ['modelo']);
      expect(p.containsKey('nombreDelDueno'), isFalse);
      expect(p.containsKey('contactosTotales'), isFalse);
    });

    test('🔴 lo que puede venir de una persona NO puede salir tal cual', () {
      // Ésta es la regla, no el cálculo. `taICual` es sólo para valores que no escribió
      // nadie: el modelo del teléfono, la versión del sistema, si es un emulador.
      const deLaPersona = CampoRecolectado(
        'nombre', Transformacion.palabras, queManda: 'cuántas palabras tiene el nombre');
      const delAparato = CampoRecolectado(
        'modelo', Transformacion.taICual, queManda: 'marca y modelo del teléfono');

      expect(deLaPersona.vieneDeUnaPersona, isTrue);
      expect(delAparato.vieneDeUnaPersona, isFalse);
    });

    test('toda ficha explica qué manda, en una frase que le sirva a alguien', () {
      const campos = [
        CampoRecolectado('modelo', Transformacion.taICual, queManda: 'marca y modelo del teléfono'),
        CampoRecolectado('nombre', Transformacion.palabras, queManda: 'cuántas palabras tiene el nombre'),
      ];
      for (final c in campos) {
        expect(c.queManda.length, greaterThan(15),
            reason: '${c.nombre}: un campo cuyo «qué manda» no se puede escribir en una '
                'frase es un campo que nadie entiende, incluidos nosotros');
      }
    });
  });
}
