import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

/// LA HUELLA VALE COMO CONSTANCIA DE REGISTRO
///
/// Este archivo existe por un error medido en pantalla el 2026-08-31: la aplicación
/// mostró «No puede recibir · no llegó a registrarse en el servidor» sobre un teléfono
/// que se había registrado tres minutos antes.
///
/// La causa: `_registrado` vive en memoria y arranca en `false` en cada apertura; la
/// huella vive en disco y sobrevive. Al segundo arranque el plan decide correctamente
/// «no hace falta registrar», y nadie levantaba la bandera.
void main() {
  final politica = PoliticaDeNotificaciones.comoEstabaAntes;
  final ahora = DateTime(2026, 8, 31, 10);

  PlanDeSesion plan({
    required HuellaDelRegistro? huella,
    String userId = 'u1',
    String? anterior = 'u1',
    String? token = 'tok',
  }) =>
      planearInicioDeSesion(
        politica: politica,
        userId: userId,
        estado: EstadoDelPermiso.concedido,
        token: token,
        userIdAnterior: anterior,
        ultimoRegistro: huella,
        yaSePregunto: true,
        desdeLaUltimaPregunta: const Duration(days: 30),
        ahora: ahora,
      );

  test('con la huella al día NO se vuelve a registrar', () {
    final huella = HuellaDelRegistro(
      userId: 'u1',
      token: 'tok',
      permisoConcedido: true,
      cuando: ahora.subtract(const Duration(minutes: 3)),
    );
    expect(plan(huella: huella).registrar, isFalse,
        reason: 'ahorrar la llamada es correcto; lo que estaba mal era no '
            'reconocer que ese registro sigue valiendo');
  });

  test('sin huella SÍ se registra', () {
    expect(plan(huella: null).registrar, isTrue);
  });

  test('si cambió el token se registra de nuevo', () {
    final huella = HuellaDelRegistro(
      userId: 'u1',
      token: 'otro',
      permisoConcedido: true,
      cuando: ahora.subtract(const Duration(minutes: 3)),
    );
    expect(plan(huella: huella).registrar, isTrue);
  });

  test('si cambió la persona se registra de nuevo', () {
    final huella = HuellaDelRegistro(
      userId: 'u1',
      token: 'tok',
      permisoConcedido: true,
      cuando: ahora.subtract(const Duration(minutes: 3)),
    );
    expect(plan(huella: huella, userId: 'u2', anterior: 'u1').registrar, isTrue);
  });

  test('el motivo con registro vigente dice que todo está en orden', () {
    // Es la línea que la persona lee en pantalla. Con `registrado: true` —que es lo
    // que ahora produce una huella al día— tiene que decir que se puede recibir.
    expect(
      motivoDeSesion(
        estado: EstadoDelPermiso.concedido,
        hayToken: true,
        registrado: true,
      ),
      contains('Todo en orden'),
    );
    expect(
      motivoDeSesion(
        estado: EstadoDelPermiso.concedido,
        hayToken: true,
        registrado: false,
      ),
      contains('no llegó a registrarse'),
    );
  });
}
