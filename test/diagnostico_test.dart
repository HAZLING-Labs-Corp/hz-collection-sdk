import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:hz_collection_sdk/src/permiso.dart' show GestorDePermiso;
import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import 'package:flutter_test/flutter_test.dart';

import 'mensajeria_falsa.dart';

/// Una cadena entera, a la que cada caso le corta un solo eslabón. Construir así
/// —desde «todo bien» hacia atrás— es lo que deja probar que gana el PRIMER
/// eslabón roto y no el último, que es el único error que este archivo no puede
/// cometer.
Diagnostico armar({
  bool hayConfig = true,
  bool configDelServidor = true,
  bool firebaseIniciado = true,
  String? appId = 'app-asignada',
  EstadoDelPermiso permiso = EstadoDelPermiso.concedido,
  bool hayToken = true,
  String? userId = 'u_1',
  bool registrado = true,
  AkPushError? ultimoError,
}) =>
    Diagnostico(
      configuracion: EstadoDeLaConfiguracion(
        hay: hayConfig,
        vieneDelServidor: configDelServidor,
        version: '7',
        comercio: 'farmatodo',
      ),
      firebase: EstadoDeFirebase(
        inicializado: firebaseIniciado,
        projectId: 'proyecto-real',
        appId: appId,
        projectIdEsperado: 'proyecto-asignado',
        appIdEsperado: 'app-asignada',
      ),
      permiso: permiso,
      token: EstadoDelToken(hay: hayToken, huella: 'cX9aQ2…8f1b'),
      registro: EstadoDelRegistro(registrado: registrado, userId: userId),
      ultimoError: ultimoError,
    );

void main() {
  group('elige el primer eslabón roto de la cadena', () {
    test('sin configuración', () {
      expect(armar(hayConfig: false).eslabonRoto, Eslabon.configuracion);
    });

    test('Firebase sin inicializar', () {
      expect(
        armar(firebaseIniciado: false, appId: null).eslabonRoto,
        Eslabon.firebase,
      );
    });

    test('Firebase inicializado con OTRA cuenta también es un eslabón roto', () {
      // Es el fallo mudo: hay token, hay registro, y aun así no llega nada.
      final d = armar(appId: 'app-de-otro-proyecto');
      expect(d.eslabonRoto, Eslabon.firebase);
      expect(d.firebase.coincideConLaConfiguracion, isFalse);
    });

    test('permiso que no deja recibir', () {
      for (final estado in [
        EstadoDelPermiso.sinPreguntar,
        EstadoDelPermiso.denegado,
        EstadoDelPermiso.denegadoParaSiempre,
      ]) {
        expect(armar(permiso: estado).eslabonRoto, Eslabon.permiso,
            reason: estado.name);
      }
    });

    test('provisional NO es un eslabón roto: los avisos llegan', () {
      expect(armar(permiso: EstadoDelPermiso.provisional).todoBien, isTrue);
    });

    test('sin token', () {
      expect(armar(hayToken: false).eslabonRoto, Eslabon.token);
    });

    test('sin identify(), y con identify() que no llegó', () {
      expect(armar(userId: null, registrado: false).eslabonRoto,
          Eslabon.registro);
      expect(armar(registrado: false).eslabonRoto, Eslabon.registro);
    });

    test('gana el primero, no el último', () {
      final todoRoto = armar(
        hayConfig: false,
        firebaseIniciado: false,
        permiso: EstadoDelPermiso.denegadoParaSiempre,
        hayToken: false,
        userId: null,
        registrado: false,
      );
      expect(todoRoto.eslabonRoto, Eslabon.configuracion);
    });

    test('cada eslabón le gana a TODOS los que vienen después', () {
      // La prueba de arriba rompe los cinco a la vez y sólo demuestra que gana
      // el primero de la lista. Ésta va corriendo el corte por la cadena: en
      // cada vuelta se rompe un eslabón y todos los que vienen después, y tiene
      // que ganar el que se rompió primero. Es lo único que distingue «elige el
      // primer eslabón roto» de «los `if` están en un orden que casualmente
      // funciona para el caso que probamos».
      //
      // Importa porque reportar el último manda a arreglar un síntoma: sin
      // configuración no hay token que conseguir, y un ticket que dice «no
      // consigue token» hace perder una tarde buscando red en un teléfono al
      // que nunca le llegó la llave.
      final cortes = <Eslabon, Diagnostico>{
        Eslabon.configuracion: armar(
          hayConfig: false,
          firebaseIniciado: false,
          appId: null,
          permiso: EstadoDelPermiso.denegado,
          hayToken: false,
          registrado: false,
        ),
        Eslabon.firebase: armar(
          firebaseIniciado: false,
          appId: null,
          permiso: EstadoDelPermiso.denegado,
          hayToken: false,
          registrado: false,
        ),
        Eslabon.permiso: armar(
          permiso: EstadoDelPermiso.denegado,
          hayToken: false,
          registrado: false,
        ),
        Eslabon.token: armar(hayToken: false, registrado: false),
        Eslabon.registro: armar(registrado: false),
        Eslabon.ninguno: armar(),
      };

      for (final corte in cortes.entries) {
        expect(corte.value.eslabonRoto, corte.key, reason: corte.key.name);
        expect(
          corte.value.todoBien,
          corte.key == Eslabon.ninguno,
          reason: corte.key.name,
        );
      }
    });

    test('un eslabón sano de más abajo no tapa al roto de más arriba', () {
      // El fallo mudo de verdad: hay token y hay alta —todo lo que se mira
      // primero cuando alguien reclama— y aun así Firebase quedó atado a otra
      // cuenta. Desde afuera se ve idéntico a «todo bien» hasta que se comparan
      // las dos cuentas.
      final d = armar(appId: 'app-de-otro-proyecto');
      expect(d.token.estaBien, isTrue);
      expect(d.registro.estaBien, isTrue);
      expect(d.eslabonRoto, Eslabon.firebase);
      expect(d.quePasa, contains('otra cuenta'));
    });

    test('la cadena entera lo dice', () {
      final d = armar();
      expect(d.todoBien, isTrue);
      expect(d.eslabonRoto, Eslabon.ninguno);
      expect(d.quePasa, contains('el problema no está en el teléfono'));
    });
  });

  group('la frase distingue lo que pide acciones distintas', () {
    test('«no se puede volver a preguntar» sólo si de verdad no se puede', () {
      expect(armar(permiso: EstadoDelPermiso.denegadoParaSiempre).quePasa,
          contains('Ajustes'));
      // Mandar a los Ajustes cuando todavía queda un diálogo del sistema tira a
      // la basura la última chance real de recuperar a esa persona.
      expect(armar(permiso: EstadoDelPermiso.denegado).quePasa,
          isNot(contains('Ajustes')));
    });

    test('el error tragado afina el diagnóstico de configuración', () {
      String frase(AkPushErrorCode code) => armar(
            hayConfig: false,
            ultimoError: AkPushError(code, 'x'),
          ).quePasa;

      expect(frase(AkPushErrorCode.unauthorized), contains('llave'));
      expect(frase(AkPushErrorCode.appMismatch), contains('paquete'));
      expect(frase(AkPushErrorCode.network), contains('conexión'));
      expect(armar(hayConfig: false).quePasa, contains('asíncrono'));
    });

    test('nunca se llamó a identify() vs. el alta que no llegó', () {
      expect(armar(userId: null, registrado: false).quePasa,
          contains('nunca se llamó a identify()'));
      expect(armar(registrado: false).quePasa, contains('«u_1»'));
    });

    test('con todo bien, avisa lo que igual puede morder', () {
      expect(armar(configDelServidor: false).quePasa, contains('guardada'));
      expect(armar(permiso: EstadoDelPermiso.provisional).quePasa,
          contains('silencio'));
    });
  });

  group('para pegar en un ticket', () {
    test('toString nombra el eslabón y no filtra el token entero', () {
      final texto = armar(permiso: EstadoDelPermiso.denegadoParaSiempre)
          .toString();
      expect(texto, contains('Eslabón roto: permiso'));
      expect(texto, contains('ROTO'));
      expect(texto, contains('cX9aQ2…8f1b'));
    });

    test('toJson lleva adentro la respuesta, para poder agrupar', () {
      final json = armar(appId: 'otra').toJson();
      expect(json['eslabonRoto'], 'firebase');
      expect(json['todoBien'], isFalse);
      expect(json['quePasa'], isA<String>());
      expect((json['firebase'] as Map)['coincide'], isFalse);
      expect(json['permiso'], 'concedido');
    });
  });

  group('no se cae ni se cuelga sin nada vivo', () {
    // Con `test()` los temporizadores son reales; dentro de `testWidgets` el
    // reloj es falso y el límite de tiempo de las lecturas nunca se dispararía.
    TestWidgetsFlutterBinding.ensureInitialized();

    test('reunir() contesta aunque no haya disco, Firebase ni mensajería',
        () async {
      final d = await Diagnostico.reunir(
        ultimoError: AkPushError(AkPushErrorCode.network, 'sin señal'),
      );
      expect(d.eslabonRoto, Eslabon.configuracion);
      expect(d.configuracion.hay, isFalse);
      expect(d.firebase.inicializado, isFalse);
      expect(d.permiso, EstadoDelPermiso.sinPreguntar);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('diagnosticar NO dispara el diálogo del permiso', () async {
      // 🔴 La regla que sostiene todo el archivo: un botón de «diagnosticar»
      // que pide el permiso le quema a la aplicación su única oportunidad de
      // pedirlo bien. El diálogo se muestra una sola vez, y gastarlo mirando el
      // problema es romper el eslabón que se venía a medir.
      final fcm = MensajeriaFalsa(estado: AuthorizationStatus.authorized);

      final d = await Diagnostico.reunir(
        gestorDePermiso: GestorDePermiso(mensajeria: fcm),
      );

      expect(d.permiso, EstadoDelPermiso.concedido);
      expect(fcm.lecturas, 1, reason: 'leer el estado sí, y una sola vez');
      expect(fcm.dialogos, 0, reason: 'esto es lo que no se puede gastar');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('un permiso ya leído no se vuelve a leer', () async {
      // El salto al canal nativo se paga en el arranque; si la fachada ya lo
      // pagó, el diagnóstico lo reutiliza en vez de cobrarlo de nuevo.
      final fcm = MensajeriaFalsa(estado: AuthorizationStatus.authorized);

      final d = await Diagnostico.reunir(
        permiso: EstadoDelPermiso.denegadoParaSiempre,
        gestorDePermiso: GestorDePermiso(mensajeria: fcm),
      );

      expect(d.permiso, EstadoDelPermiso.denegadoParaSiempre);
      expect(fcm.lecturas, 0);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
