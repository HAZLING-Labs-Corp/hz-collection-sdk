import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ahora = DateTime(2026, 8, 30, 12);

  HuellaDelRegistro huella({
    String userId = 'u1',
    String token = 't1',
    bool permiso = true,
    Duration antiguedad = Duration.zero,
  }) =>
      HuellaDelRegistro(
        userId: userId,
        token: token,
        permisoConcedido: permiso,
        cuando: ahora.subtract(antiguedad),
      );

  PlanDeSesion planear({
    PoliticaDeNotificaciones? politica,
    String userId = 'u1',
    EstadoDelPermiso estado = EstadoDelPermiso.concedido,
    String? token = 't1',
    String? anterior,
    HuellaDelRegistro? ultimo,
    int maxDias = 7,
  }) =>
      planearInicioDeSesion(
        politica: politica ?? PoliticaDeNotificaciones.comoEstabaAntes,
        userId: userId,
        estado: estado,
        token: token,
        userIdAnterior: anterior,
        ultimoRegistro: ultimo,
        yaSePregunto: false,
        ahora: ahora,
        maxDiasSinRevalidar: maxDias,
      );

  group('el plan del inicio de sesión', () {
    test('sin huella previa, registra', () {
      expect(planear().registrar, isTrue);
    });

    test('si nada cambió, no vuelve a llamar al servidor', () {
      expect(planear(ultimo: huella()).registrar, isFalse);
    });

    test('si cambió el token, registra', () {
      expect(planear(ultimo: huella(token: 'viejo')).registrar, isTrue);
    });

    test('si cambió el permiso con el mismo token, registra igual', () {
      // Es el caso de quien concede el permiso desde los Ajustes del teléfono:
      // el token no cambia y el servidor tiene que enterarse, porque filtra por
      // eso antes de enviar. Comparar sólo el token la dejaría sin recibir para
      // siempre.
      expect(planear(ultimo: huella(permiso: false)).registrar, isTrue);
    });

    test('sin token no hay nada que registrar', () {
      // No es un fallo: es lo que pasa cuando la persona no dio permiso.
      expect(planear(token: null, estado: EstadoDelPermiso.denegado).registrar,
          isFalse);
    });
  });

  group('el teléfono que cambia de manos', () {
    test('si entra otra persona, se da de baja a la anterior', () {
      final p = planear(userId: 'u2', anterior: 'u1');
      expect(p.darDeBajaALaAnterior, isTrue);
    });

    test('la misma persona no se da de baja a sí misma', () {
      expect(planear(userId: 'u1', anterior: 'u1').darDeBajaALaAnterior, isFalse);
    });

    test('🔴 si cambió la persona, registra aunque el estado sea idéntico', () {
      // La huella era de OTRA persona. Compararse contra ella dejaría a la
      // nueva sin registrar, y es un fallo silencioso: el teléfono queda
      // asociado a quien ya no lo usa.
      final p = planear(
        userId: 'u2',
        anterior: 'u1',
        ultimo: huella(userId: 'u1'),
      );
      expect(p.registrar, isTrue);
    });
  });

  group('la huella vence, porque es local y puede mentir', () {
    test('una huella fresca no obliga a registrar', () {
      expect(planear(ultimo: huella(antiguedad: const Duration(days: 2))).registrar,
          isFalse);
    });

    test('una vencida sí, aunque nada haya cambiado', () {
      // El servidor pudo haber limpiado este dispositivo y el teléfono no tiene
      // forma de enterarse. No se detecta: se acota.
      expect(planear(ultimo: huella(antiguedad: const Duration(days: 8))).registrar,
          isTrue);
    });

    test('el plazo se puede ajustar', () {
      final vieja = huella(antiguedad: const Duration(days: 3));
      expect(planear(ultimo: vieja, maxDias: 2).registrar, isTrue);
      expect(planear(ultimo: vieja, maxDias: 30).registrar, isFalse);
    });

    test('una huella sin fecha —de una versión anterior— se trata como vencida', () {
      final vieja = HuellaDelRegistro.fromJson(
          {'userId': 'u1', 'token': 't1', 'permisoConcedido': true});
      expect(vieja!.vencio(ahora, 7), isTrue,
          reason: 'se registra una vez y queda sana, en vez de descartar el dato');
    });
  });

  group('el motivo', () {
    test('elige el primer eslabón roto, no cualquiera', () {
      // De nada sirve decir «no está registrada» si además denegó el permiso:
      // arreglar lo segundo no cambiaría nada.
      final m = motivoDeSesion(
        estado: EstadoDelPermiso.denegadoParaSiempre,
        hayToken: false,
        registrado: false,
      );
      expect(m, contains('Ajustes'));
    });

    test('distingue denegado de denegado para siempre', () {
      expect(
        motivoDeSesion(
            estado: EstadoDelPermiso.denegado, hayToken: false, registrado: false),
        contains('volver a preguntar'),
      );
    });

    test('cuando está todo bien, lo dice', () {
      expect(
        motivoDeSesion(
            estado: EstadoDelPermiso.concedido, hayToken: true, registrado: true),
        contains('puede recibir'),
      );
    });
  });
}
