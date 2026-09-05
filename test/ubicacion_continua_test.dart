import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// `geolocator` reexporta la interfaz de plataforma entera, así que se importa desde acá:
// nombrar `geolocator_platform_interface` directo sería depender de un paquete que este
// `pubspec` no declara, y el día que geolocator lo cambie de versión esto se rompe solo.
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hz_collection_sdk/src/api_client.dart';
import 'package:hz_collection_sdk/src/diagnostico.dart';
import 'package:hz_collection_sdk/src/politica.dart';
import 'package:hz_collection_sdk/src/ubicacion.dart';

/// LO QUE ESTAS PRUEBAS CUIDAN, Y POR QUÉ NO ES OBVIO.
///
/// La ubicación en segundo plano tiene un modo de fallar que no se parece a un error: el
/// comercio la prende en su consola, ve el interruptor en verde, le dice a la persona
/// «instalá la aplicación y esperá quince días», y a los quince días no hay ni una lectura
/// — porque a la aplicación le faltaba un renglón en el manifiesto que ni el SDK ni la
/// consola pueden poner por ella.
///
/// Casi todo lo de acá abajo prueba ese caso, desde ángulos distintos.

/// Un `geolocator` de mentira. Es la única forma de probar esto sin un teléfono: las tres
/// preguntas que decide el sistema —permiso, interruptor y qué posición hay— se contestan
/// acá, y lo que se prueba es lo que el SDK hace con las respuestas.
class GeolocatorFalso extends GeolocatorPlatform {
  GeolocatorFalso({
    this.permiso = LocationPermission.whileInUse,
    this.servicio = true,
  });

  LocationPermission permiso;
  bool servicio;
  int vecesQueSeAbrioElFlujo = 0;
  final _controlador = StreamController<Position>.broadcast();

  @override
  Future<LocationPermission> checkPermission() async => permiso;

  @override
  Future<LocationPermission> requestPermission() async => permiso;

  @override
  Future<bool> isLocationServiceEnabled() async => servicio;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    vecesQueSeAbrioElFlujo++;
    return _controlador.stream;
  }

  void emitir(Position p) => _controlador.add(p);

  Future<void> cerrar() => _controlador.close();
}

Position _posicion(DateTime cuando) => Position(
      latitude: 10.5,
      longitude: -66.9,
      timestamp: cuando,
      accuracy: 2000,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canal = MethodChannel('hz_collection_sdk/senales');
  final mensajero =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Contesta lo que contestaría el plugin nativo. `null` = el plugin no está, que es lo
  /// que pasa en una prueba sin teléfono y también en una plataforma sin implementar.
  void elPluginContesta(Map<String, Object?>? respuesta) {
    mensajero.setMockMethodCallHandler(canal, (llamada) async {
      if (llamada.method != 'puedeSegundoPlano') return null;
      if (respuesta == null) throw MissingPluginException();
      return respuesta;
    });
  }

  late GeolocatorFalso sistema;
  late List<Map<String, dynamic>> mandadas;
  late AkPushApi api;

  setUp(() {
    sistema = GeolocatorFalso();
    GeolocatorPlatform.instance = sistema;
    mandadas = [];
    api = AkPushApi(
      apiKey: 'k',
      baseUrl: 'https://ejemplo.test',
      cliente: MockClient((p) async {
        mandadas.add({'url': '${p.url}', 'body': p.body});
        return http.Response('{}', 200);
      }),
    );
  });

  tearDown(() async {
    mensajero.setMockMethodCallHandler(canal, null);
    await sistema.cerrar();
  });

  // ══ LA POLÍTICA ═══════════════════════════════════════════════════════════════════

  group('la política de lectura', () {
    test('por omisión es lo de siempre: una lectura al entrar', () {
      const p = PoliticaDeUbicacion();
      expect(p.modo, ModoDeLectura.alEntrar);
      expect(p.cada, Duration.zero);
    });

    test('un comercio que no configuró nada no cambia de comportamiento', () {
      // El caso real: el servicio todavía no manda el campo. Nadie ve un cambio por
      // actualizar el paquete, que es la única forma de agregar esto sin romper a nadie.
      final p = PoliticaDeUbicacion.fromJson({'activa': true});
      expect(p.modo, ModoDeLectura.alEntrar);
    });

    test('los tres modos se leen del servidor', () {
      expect(
        PoliticaDeUbicacion.fromJson({'modo': 'enPrimerPlano'}).modo,
        ModoDeLectura.enPrimerPlano,
      );
      expect(
        PoliticaDeUbicacion.fromJson({'modo': 'enSegundoPlano'}).modo,
        ModoDeLectura.enSegundoPlano,
      );
    });

    test('🔴 una palabra desconocida cae al modo más barato, nunca al más caro', () {
      // Si cayera hacia arriba, un error de tipeo del servicio prendería un servicio en
      // segundo plano en los teléfonos de todo un comercio.
      for (final basura in ['ensegundoplano', 'continuo', '', 'null']) {
        expect(
          PoliticaDeUbicacion.fromJson({'modo': basura}).modo,
          ModoDeLectura.alEntrar,
          reason: 'con «$basura» tiene que quedarse en alEntrar',
        );
      }
    });

    test('la frecuencia por omisión es conservadora: 30 min en el fondo, 2 en el frente',
        () {
      final fondo =
          PoliticaDeUbicacion.fromJson({'modo': 'enSegundoPlano'});
      expect(fondo.cada, const Duration(minutes: 30));

      final frente =
          PoliticaDeUbicacion.fromJson({'modo': 'enPrimerPlano'});
      expect(frente.cada, const Duration(minutes: 2));
    });

    test('🔴 el piso no se puede saltar desde la consola', () {
      // Un cero en la consola no puede dejar el teléfono leyendo sin parar toda la noche.
      final p = PoliticaDeUbicacion.fromJson({
        'modo': 'enSegundoPlano',
        'cadaMinutosEnSegundoPlano': 0,
      });
      expect(p.cada, const Duration(minutes: 5));
    });

    test('los textos de «siempre» son propios y caen campo por campo', () {
      final p = PoliticaDeUbicacion.fromJson({
        'modo': 'enSegundoPlano',
        'textosDeSiempre': {'titulo': 'Todo el día'},
      });
      expect(p.textosDeSiempre.titulo, 'Todo el día');
      // Quien cambió sólo el título no se queda sin el resto.
      expect(p.textosDeSiempre.motivos, isNotEmpty);
      expect(p.textosDeSiempre.avisoTitulo, isNotEmpty);
    });
  });

  // ══ EL SEGUNDO PLANO QUE SE APAGA SOLO ════════════════════════════════════════════

  group('el segundo plano sin el permiso declarado', () {
    test('🔴 no arranca, y DICE por qué', () async {
      elPluginContesta({
        'sePuede': false,
        'faltan': ['android.permission.ACCESS_BACKGROUND_LOCATION'],
      });
      final u = Ubicacion(api);

      final motivo = await u.arrancarContinuo(
        userId: 'u1',
        modo: ModoDeLectura.enSegundoPlano,
        cada: const Duration(minutes: 30),
      );

      expect(motivo, isNotNull);
      expect(motivo, contains('ACCESS_BACKGROUND_LOCATION'));
      expect(u.ultimoMotivo, motivo);
      // Y sobre todo: NO abrió ningún flujo. Nada de «midió pero no mandó».
      expect(sistema.vecesQueSeAbrioElFlujo, 0);
    });

    test('🔴 el modo pedido y el que corre quedan separados', () async {
      elPluginContesta({'sePuede': false, 'faltan': ['lo que sea']});
      final u = Ubicacion(api);
      await u.arrancarContinuo(
        userId: 'u1',
        modo: ModoDeLectura.enSegundoPlano,
        cada: const Duration(minutes: 30),
      );
      // Ésta es la distinción que hace visible el fallo: con un solo campo, este comercio
      // se vería igual que uno que nunca pidió nada.
      expect(u.modoPedido, ModoDeLectura.enSegundoPlano);
      expect(u.modoActivo, ModoDeLectura.alEntrar);
    });

    test('🔴 si no se puede preguntar, la respuesta es que NO se puede', () async {
      // Sin plugin —otra plataforma, una versión vieja del APK—, fallar hacia el modo caro
      // sería prender un servicio en el fondo a ciegas.
      elPluginContesta(null);
      final u = Ubicacion(api);
      expect(await u.sePuedeEnSegundoPlano, isFalse);
      expect(u.faltaDeclarar, isNotEmpty);
    });

    test('con el permiso declarado pero sin el «siempre» de la persona, tampoco arranca',
        () async {
      elPluginContesta({'sePuede': true, 'faltan': <String>[]});
      sistema.permiso = LocationPermission.whileInUse; // dio la zona, no el siempre
      final u = Ubicacion(api);

      final motivo = await u.arrancarContinuo(
        userId: 'u1',
        modo: ModoDeLectura.enSegundoPlano,
        cada: const Duration(minutes: 30),
      );
      expect(motivo, contains('Permitir siempre'));
      expect(sistema.vecesQueSeAbrioElFlujo, 0);
    });

    test('con todo en su lugar, arranca', () async {
      elPluginContesta({'sePuede': true, 'faltan': <String>[]});
      sistema.permiso = LocationPermission.always;
      final u = Ubicacion(api);

      expect(
        await u.arrancarContinuo(
          userId: 'u1',
          modo: ModoDeLectura.enSegundoPlano,
          cada: const Duration(minutes: 30),
        ),
        isNull,
      );
      expect(u.modoActivo, ModoDeLectura.enSegundoPlano);
      expect(sistema.vecesQueSeAbrioElFlujo, 1);
      await u.detenerContinuo();
    });
  });

  // ══ EL PRIMER PLANO: NINGÚN PERMISO NUEVO ═════════════════════════════════════════

  group('el primer plano', () {
    test('🔴 no le pregunta nada al manifiesto: no necesita ningún permiso nuevo',
        () async {
      // Si el plugin ni contesta, el primer plano tiene que arrancar igual. Que dependa de
      // la declaración de segundo plano sería atarle un costo que no tiene.
      elPluginContesta(null);
      final u = Ubicacion(api);

      expect(
        await u.arrancarContinuo(
          userId: 'u1',
          modo: ModoDeLectura.enPrimerPlano,
          cada: const Duration(minutes: 2),
        ),
        isNull,
      );
      expect(u.modoActivo, ModoDeLectura.enPrimerPlano);
      await u.detenerContinuo();
    });

    test('sin el permiso de la zona no arranca, y el motivo es ése', () async {
      sistema.permiso = LocationPermission.denied;
      final u = Ubicacion(api);
      final motivo = await u.arrancarContinuo(
        userId: 'u1',
        modo: ModoDeLectura.enPrimerPlano,
        cada: const Duration(minutes: 2),
      );
      expect(motivo, contains('no tiene permiso'));
    });

    test('con la ubicación del teléfono apagada tampoco, y el motivo es OTRO', () async {
      // Son dos causas distintas con dos arreglos distintos, y confundirlas ya costó tres
      // diagnósticos a mano en un día.
      sistema.servicio = false;
      final u = Ubicacion(api);
      final motivo = await u.arrancarContinuo(
        userId: 'u1',
        modo: ModoDeLectura.enPrimerPlano,
        cada: const Duration(minutes: 2),
      );
      expect(motivo, contains('ubicación apagada'));
    });
  });

  // ══ EL RELOJ, QUE ES LO QUE PROTEGE LOS 60 HUECOS DEL SERVICIO ════════════════════

  group('cuántas salen de verdad', () {
    test('🔴 la primera sale y las que llegan antes del intervalo se descartan', () async {
      final u = Ubicacion(api);
      await u.arrancarContinuo(
        userId: 'u1',
        modo: ModoDeLectura.enPrimerPlano,
        cada: const Duration(minutes: 30),
      );

      // Tres lecturas seguidas, como las que entrega CoreLocation al moverse.
      for (var i = 0; i < 3; i++) {
        sistema.emitir(_posicion(DateTime.now()));
      }
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(u.lecturasDeLaSesion, 3, reason: 'se leyeron tres');
      expect(u.enviosDeLaSesion, 1,
          reason: 'pero sólo una salió: el resto llegó antes del intervalo');
      expect(mandadas.length, 1);
      expect(mandadas.single['url'], contains('/api/v1/ubicacion'));
      await u.detenerContinuo();
    });

    test('detener corta el flujo y vuelve al modo de siempre', () async {
      final u = Ubicacion(api);
      await u.arrancarContinuo(
        userId: 'u1',
        modo: ModoDeLectura.enPrimerPlano,
        cada: const Duration(minutes: 2),
      );
      await u.detenerContinuo();

      sistema.emitir(_posicion(DateTime.now()));
      await Future<void>.delayed(Duration.zero);

      expect(u.modoActivo, ModoDeLectura.alEntrar);
      expect(mandadas, isEmpty);
    });

    test('pedir el mismo modo dos veces no abre dos flujos', () async {
      final u = Ubicacion(api);
      for (var i = 0; i < 3; i++) {
        await u.arrancarContinuo(
          userId: 'u1',
          modo: ModoDeLectura.enPrimerPlano,
          cada: const Duration(minutes: 2),
        );
      }
      expect(sistema.vecesQueSeAbrioElFlujo, 1);
      await u.detenerContinuo();
    });

    test('el modo alEntrar no abre ningún flujo', () async {
      final u = Ubicacion(api);
      expect(
        await u.arrancarContinuo(
          userId: 'u1',
          modo: ModoDeLectura.alEntrar,
          cada: Duration.zero,
        ),
        isNull,
      );
      expect(sistema.vecesQueSeAbrioElFlujo, 0);
    });
  });

  // ══ QUE EL DIAGNÓSTICO LO DIGA ════════════════════════════════════════════════════

  group('el diagnóstico', () {
    test('🔴 el modo que no arrancó se ve, aunque los dos interruptores estén bien', () {
      const e = EstadoDeUbicacion(
        permitida: true,
        servicioPrendido: true,
        modoPedido: 'enSegundoPlano',
        modoActivo: 'alEntrar',
        faltaDeclarar: ['android.permission.ACCESS_BACKGROUND_LOCATION'],
      );
      expect(e.elModoNoArranco, isTrue);
      expect(e.toJson()['faltaDeclarar'], isNotEmpty);
    });

    test('sin modo continuo pedido, nada cambia respecto de antes', () {
      const e = EstadoDeUbicacion(permitida: true, servicioPrendido: true);
      expect(e.elModoNoArranco, isFalse);
      expect(e.toJson()['faltaDeclarar'], isNull);
    });

    test('🔴 cortarlo a propósito NO deja el diagnóstico en rojo', () async {
      // El caso: la persona pausa el seguimiento desde una pantalla del comercio, o se
      // cierra la sesión. Si `detener` bajara sólo el modo activo, el diagnóstico diría
      // «pidió enSegundoPlano y corre alEntrar» — ROTO — por algo que se hizo bien.
      final u = Ubicacion(api);
      await u.arrancarContinuo(
        userId: 'u1',
        modo: ModoDeLectura.enPrimerPlano,
        cada: const Duration(minutes: 2),
      );
      expect(u.modoPedido, ModoDeLectura.enPrimerPlano);

      await u.detenerContinuo();
      expect(u.modoPedido, ModoDeLectura.alEntrar);
      expect(u.modoActivo, ModoDeLectura.alEntrar);
    });

    test('🔴 no poder preguntar no se cachea: el próximo intento vuelve a preguntar',
        () async {
      // Esto se puede llamar antes de que el plugin se enganche al motor. Cachear ese
      // tropiezo dejaría el segundo plano apagado por el resto de la vida del proceso.
      elPluginContesta(null);
      final u = Ubicacion(api);
      expect(await u.sePuedeEnSegundoPlano, isFalse);

      elPluginContesta({'sePuede': true, 'faltan': <String>[]});
      expect(await u.sePuedeEnSegundoPlano, isTrue);
    });
  });
}
