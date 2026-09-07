import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:hz_collection_sdk/src/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AkPushConfig', () {
    /// La forma EXACTA que devuelve `GET /api/v1/configuracion`.
    const delServicio = {
      'ok': true,
      'comercio': 'mundototal',
      'version': 1,
      'firebase': {
        'projectId': 'mundototal-72162',
        'appId': '1:859769563262:android:69c967f8f8d0a8c516902f',
        'apiKey': 'AIza-falsa-para-la-prueba',
        'messagingSenderId': '859769563262',
      },
    };

    test('lee la respuesta del servicio tal cual llega', () {
      final c = AkPushConfig.fromJson(delServicio);
      expect(c.projectId, 'mundototal-72162');
      expect(c.messagingSenderId, '859769563262');
      expect(c.comercio, 'mundototal');
    });

    test('la versión llega como número y se guarda como texto', () {
      // El servicio la manda como número. Lo único que importa es comparar si
      // cambió, así que se normaliza a texto en vez de arrastrar dos tipos.
      final c = AkPushConfig.fromJson(delServicio);
      expect(c.version, '1');
    });

    test('sobrevive a la ida y vuelta del guardado', () {
      // Lo que se guarda tiene que poder releerse con el mismo fromJson que lo
      // que llega por la red: dos formas distintas serían dos maneras de
      // romperse.
      final ida = AkPushConfig.fromJson(delServicio);
      final vuelta = AkPushConfig.fromJson(ida.toJson());
      expect(vuelta.appId, ida.appId);
      expect(vuelta.version, ida.version);
      expect(vuelta.comercio, ida.comercio);
    });

    test('una versión distinta se distingue — es lo que evita el teléfono mudo', () {
      final a = AkPushConfig.fromJson(delServicio);
      final b = AkPushConfig.fromJson({...delServicio, 'version': 2});
      expect(a.version == b.version, isFalse);
    });

    test('traduce a las opciones que espera Firebase', () {
      final o = AkPushConfig.fromJson(delServicio).toFirebaseOptions();
      expect(o.projectId, 'mundototal-72162');
      expect(o.appId, '1:859769563262:android:69c967f8f8d0a8c516902f');
    });

    test('sin `modulos` —una versión vieja del servicio— queda vacío, no rompe', () {
      final c = AkPushConfig.fromJson(delServicio);
      expect(c.modulos, isEmpty);
    });
  });

  group('el catálogo de módulos', () {
    /// La forma EXACTA del catálogo que describe el contrato del rediseño.
    const conModulos = {
      'ok': true,
      'version': 1,
      'firebase': {
        'projectId': 'mundototal-72162',
        'appId': '1:859769563262:android:69c967f8f8d0a8c516902f',
        'apiKey': 'AIza-falsa-para-la-prueba',
        'messagingSenderId': '859769563262',
      },
      'modulos': {
        'avisos': {
          'nivel': 1,
          'cadencia': 'evento',
          'permisos': ['POST_NOTIFICATIONS'],
          'estado': 'activo',
        },
        'ubicacion': {
          'nivel': 1,
          'cadencia': 'periodica',
          'permisos': ['ACCESS_COARSE_LOCATION'],
          'estado': 'activo',
        },
        'rastreo': {
          'nivel': 3,
          'cadencia': 'continua',
          'permisos': ['ACCESS_BACKGROUND_LOCATION'],
          'estado': 'declarado',
        },
      },
    };

    test('se parsea con la clave siendo el nombre del módulo', () {
      final c = AkPushConfig.fromJson(conModulos);
      expect(c.modulos.keys, containsAll(['avisos', 'ubicacion', 'rastreo']));
      expect(c.modulos['avisos']!.nivel, 1);
      expect(c.modulos['avisos']!.cadencia, 'evento');
      expect(c.modulos['avisos']!.permisos, ['POST_NOTIFICATIONS']);
    });

    test('«activo» está construido, «declarado» todavía no', () {
      final c = AkPushConfig.fromJson(conModulos);
      expect(c.modulos['avisos']!.construido, isTrue);
      // 🔴 `rastreo` tiene lugar en el modelo pero no está implementado: un
      // comercio que lo vea acá no puede asumir que hace algo.
      expect(c.modulos['rastreo']!.construido, isFalse);
    });

    test('sobrevive a la ida y vuelta del guardado, como el resto de la config', () {
      final ida = AkPushConfig.fromJson(conModulos);
      final vuelta = AkPushConfig.fromJson(ida.toJson());
      expect(vuelta.modulos.keys, ida.modulos.keys);
      expect(vuelta.modulos['avisos']!.estado, 'activo');
      expect(vuelta.modulos['rastreo']!.estado, 'declarado');
    });

    test('un módulo sin permisos declarados no rompe: queda una lista vacía', () {
      final c = AkPushConfig.fromJson({
        ...conModulos,
        'modulos': {
          'senales': {'nivel': 0, 'cadencia': 'episodica', 'estado': 'declarado'},
        },
      });
      expect(c.modulos['senales']!.permisos, isEmpty);
    });
  });

  group('AccionDePush', () {
    test('los cinco valores son los que el servicio espera', () {
      expect(AccionDePush.delivered.valor, 'DELIVERED');
      expect(AccionDePush.viewed.valor, 'VIEWED');
      expect(AccionDePush.opened.valor, 'OPENED');
      expect(AccionDePush.dismissed.valor, 'DISMISSED');
      expect(AccionDePush.expired.valor, 'EXPIRED');
    });
  });

  group('la dirección se normaliza', () {
    test('acepta la URL tal como la muestra la consola, con /api/v1', () {
      // La consola le dice al comercio que la dirección es
      // «http://…:3085/api/v1». Quien la siga al pie de la letra la pega
      // completa, y sin normalizar la petición sale a /api/v1/api/v1/… — el
      // servidor contesta su 404 genérico y el error no se parece en nada a
      // «el prefijo está dos veces».
      expect(AkPushApi.normalizarUrl('http://x:3085/api/v1'), 'http://x:3085');
      expect(AkPushApi.normalizarUrl('http://x:3085/api/v1/'), 'http://x:3085');
    });

    test('y también sin él', () {
      expect(AkPushApi.normalizarUrl('http://x:3085'), 'http://x:3085');
      expect(AkPushApi.normalizarUrl('http://x:3085/'), 'http://x:3085');
    });

    test('no se come un /api/v1 que esté en el medio', () {
      expect(AkPushApi.normalizarUrl('http://x/api/v1/proxy'),
          'http://x/api/v1/proxy');
    });
  });
}
