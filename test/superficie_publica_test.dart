import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

/// Que el paquete compile no prueba que se pueda USAR desde afuera.
///
/// Un nombre que falta en el `show` de `lib/hz_collection_sdk.dart` no rompe ni el
/// análisis ni ninguna prueba interna: todo adentro sigue viéndose. El único que
/// se entera es quien integra, cuando ya se publicó. Este archivo importa **sólo
/// la puerta pública** y toca cada cosa que la fachada promete, para que esa
/// falta se vea acá y no allá.
void main() {
  // Con `testWidgets` el reloj es falso y los `.timeout()` de `Diagnostico` no
  // se disparan nunca, así que una prueba de `reunir()` ahí se cuelga sin decir
  // por qué. Va con `test()` y el binding a mano.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('el estado del permiso se puede nombrar y consultar desde afuera', () {
    const EstadoDelPermiso estado = EstadoDelPermiso.provisional;
    expect(estado.permiteRecibir, isTrue);
    expect(estado.puedeVolverAPreguntarse, isTrue);
    expect(EstadoDelPermiso.denegadoParaSiempre.soloQuedanLosAjustes, isTrue);

    // Sin `init()` no hay permiso, y eso es una respuesta, no un fallo.
    expect(AkPush.tienePermiso, isFalse);
  });

  test('la decisión de dibujo se registra y se saca sin pasar por init()',
      () async {
    DecisionDeDibujo sinRuido(PushMessage _) =>
        DecisionDeDibujo.mostrarSilencioso;

    expect(AkPush.alDecidirDibujo, isNull);

    // Se registra ANTES de init() a propósito: el portero no depende del
    // arranque, y ésa es la garantía de que el callback no se pisa al
    // inicializar.
    AkPush.alDecidirDibujo = sinRuido;
    final DecidirDibujo? registrado = AkPush.alDecidirDibujo;
    expect(registrado, isNotNull);
    expect(
      await registrado!(const PushMessage(data: {}, title: 'x')),
      DecisionDeDibujo.mostrarSilencioso,
    );

    expect(DecisionDeDibujo.mostrarSilencioso.seDibuja, isTrue);
    expect(DecisionDeDibujo.mostrarSilencioso.sinRuido, isTrue);
    expect(DecisionDeDibujo.noMostrar.seDibuja, isFalse);

    AkPush.alDecidirDibujo = null;
  });

  test('la ruta del aviso y su intención se usan desde la fachada', () async {
    const aviso = PushMessage(
      data: {'ruta': '/compras/:id', 'ruta_id': '9912'},
      title: 'Tu compra fue aprobada',
    );

    // La extensión `AvisoConRuta` sólo existe del otro lado si está en el
    // `show`: sin ella estas dos líneas ni siquiera compilan.
    expect(aviso.tieneRuta, isTrue);
    expect(aviso.ruta?.destino, '/compras/9912');
    expect(RutaDelAviso.desde(aviso)?.parametros['id'], '9912');

    IntencionPendiente.instancia.guardarDesde(aviso);
    expect(AkPush.rutaPendiente.value?.destino, '/compras/9912');

    final entregadas = <String>[];
    final cortar = AkPush.alRutear((r) => entregadas.add(r.destino));
    await Future<void>.delayed(Duration.zero);
    cortar();

    expect(entregadas, ['/compras/9912']);
    // Se entrega una sola vez: quien llegue después no la vuelve a navegar.
    expect(AkPush.consumirRuta(), isNull);
  });

  test('diagnostico() contesta aunque init() nunca se haya llamado', () async {
    // Éste es el caso número uno de soporte y el motivo por el que
    // `diagnostico()` no pasa por `_asegurarIniciado()`: sin plugins, sin
    // Firebase y sin disco tiene que contestar igual, y rápido.
    final d = await AkPush.diagnostico().timeout(const Duration(seconds: 10));

    expect(d.todoBien, isFalse);
    expect(d.eslabonRoto, Eslabon.configuracion);
    expect(d.quePasa, contains('init()'));
    expect(d.toJson()['eslabonRoto'], 'configuracion');
    expect(d.toString(), contains('AkPush — diagnóstico'));
  });

  test('identify() antes de tiempo lo dice, en vez de fallar mudo', () async {
    // El error clásico de integración: `init()` es asíncrono y el botón de
    // inicio de sesión no espera. Sin este aviso, `identify()` se iría sin
    // hacer nada y el teléfono quedaría sin registrar, sin ningún síntoma
    // hasta que alguien reclame que no le llegan los avisos.
    await expectLater(
      AkPush.identify(userId: 'u_887'),
      throwsA(
        isA<AkPushError>()
            .having((e) => e.code, 'code', AkPushErrorCode.notInitialized)
            .having((e) => e.retryable, 'retryable', isFalse)
            .having((e) => e.details, 'details', contains('asíncrono')),
      ),
    );
  });

  test('reportar un aviso sin pushLogId no rompe ni inventa nada', () async {
    // Las tres acciones que reporta la aplicación —vista, descartada,
    // caducada— se llaman desde su código, y ahí puede llegar cualquier aviso.
    // Uno sin identificador de envío no tiene nada que medir: se ignora en
    // silencio y no se le tira una excepción a quien sólo estaba marcando que
    // la persona lo vio.
    await AkPush.reportar(
      const PushMessage(data: {}, title: 'sin identificador'),
      AccionDePush.viewed,
    );
  });
}
