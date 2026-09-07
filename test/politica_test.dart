import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PoliticaDeNotificaciones', () {
    test('sin configuración del servidor, se comporta como antes', () {
      // Es la garantía de que traer esto no le cambia el comportamiento a nadie
      // mientras el servicio todavía no sirva el campo.
      final p = PoliticaDeNotificaciones.fromJson(null);
      expect(p.momento, MomentoDelPermiso.arranque);
      expect(p.obligatorio, isFalse);
      expect(p.preguntaBlanda, isFalse);
    });

    test('un momento desconocido no rompe: cae en el que ya andaba', () {
      // Si mañana el servicio agrega un momento nuevo, una app vieja tiene que
      // seguir arrancando en vez de fallar por una palabra que no conoce.
      final p = PoliticaDeNotificaciones.fromJson({'momento': 'cuandoSalgaLaLuna'});
      expect(p.momento, MomentoDelPermiso.arranque);
    });

    test('lee lo que manda el servidor', () {
      final p = PoliticaDeNotificaciones.fromJson({
        'momento': 'login',
        'obligatorio': true,
        'preguntaBlanda': true,
        'reintentarCadaDias': 3,
        'textos': {'titulo': 'Avisos de tu crédito'},
      });
      expect(p.momento, MomentoDelPermiso.login);
      expect(p.obligatorio, isTrue);
      expect(p.reintentarCadaDias, 3);
      expect(p.textos.titulo, 'Avisos de tu crédito');
      // Lo que no vino, queda en el predeterminado.
      expect(p.textos.ahoraNo, 'Ahora no');
    });
  });

  group('decidirQueHacer', () {
    AccionDePermiso decidir({
      PoliticaDeNotificaciones? politica,
      Disparador disparador = Disparador.arranque,
      EstadoDelPermiso estado = EstadoDelPermiso.sinPreguntar,
      bool yaSePregunto = false,
      Duration? desde,
    }) =>
        decidirQueHacer(
          politica: politica ?? PoliticaDeNotificaciones.comoEstabaAntes,
          disparador: disparador,
          estado: estado,
          yaSePregunto: yaSePregunto,
          desdeLaUltimaPregunta: desde,
        );

    test('si ya está concedido no se hace nada, pase lo que pase', () {
      expect(decidir(estado: EstadoDelPermiso.concedido), AccionDePermiso.ninguna);
      expect(
        decidir(
          estado: EstadoDelPermiso.concedido,
          politica: const PoliticaDeNotificaciones(obligatorio: true),
        ),
        AccionDePermiso.ninguna,
      );
      // `provisional` de iOS también entrega, así que tampoco hay nada que pedir.
      expect(decidir(estado: EstadoDelPermiso.provisional), AccionDePermiso.ninguna);
    });

    test('denegado para siempre: sólo se ofrecen los Ajustes si el comercio lo exige', () {
      // Insistir con los Ajustes por algo que la persona ya contestó, y que el
      // comercio no considera indispensable, es molestar.
      expect(decidir(estado: EstadoDelPermiso.denegadoParaSiempre), AccionDePermiso.ninguna);
      expect(
        decidir(
          estado: EstadoDelPermiso.denegadoParaSiempre,
          politica: const PoliticaDeNotificaciones(obligatorio: true),
        ),
        AccionDePermiso.ofrecerAjustes,
      );
    });

    test('respeta el momento que eligió el comercio', () {
      const enLogin = PoliticaDeNotificaciones(momento: MomentoDelPermiso.login);
      expect(decidir(politica: enLogin, disparador: Disparador.arranque),
          AccionDePermiso.ninguna);
      expect(decidir(politica: enLogin, disparador: Disparador.login),
          AccionDePermiso.pedirAlSistema);
    });

    test('«arranque» que no llegó a preguntar se rescata en el primer login', () {
      // El defecto que esto cubre: NADIE en el SDK pasa `Disparador.arranque`, así que
      // un comercio con la política en «arranque» no recibía ningún diálogo nunca.
      // Visto en el teléfono de Juan el 2026-09-05: entró y tuvo que tocar la campanita.
      const enArranque = PoliticaDeNotificaciones();
      expect(decidir(politica: enArranque, disparador: Disparador.login),
          AccionDePermiso.pedirAlSistema);
    });

    test('pero si el arranque YA preguntó, el login no vuelve a preguntar', () {
      // El rescate no puede convertirse en dos diálogos seguidos.
      const enArranque = PoliticaDeNotificaciones(reintentarCadaDias: 7);
      expect(
        decidir(
          politica: enArranque,
          disparador: Disparador.login,
          yaSePregunto: true,
          desde: const Duration(hours: 1),
        ),
        AccionDePermiso.ninguna,
      );
    });

    test('el rescate respeta la pregunta blanda del comercio', () {
      const blandaEnArranque = PoliticaDeNotificaciones(preguntaBlanda: true);
      expect(decidir(politica: blandaEnArranque, disparador: Disparador.login),
          AccionDePermiso.mostrarPreguntaBlanda);
    });

    test('con «la app decide», el SDK no pide nada por su cuenta', () {
      const laApp = PoliticaDeNotificaciones(momento: MomentoDelPermiso.laAppDecide);
      expect(decidir(politica: laApp, disparador: Disparador.arranque),
          AccionDePermiso.ninguna);
      expect(decidir(politica: laApp, disparador: Disparador.login),
          AccionDePermiso.ninguna);
      expect(decidir(politica: laApp, disparador: Disparador.laAppLoPidio),
          AccionDePermiso.pedirAlSistema);
    });

    test('cuando la app lo pide explícitamente, se le hace caso siempre', () {
      // Negarse porque «no es el momento» sería desobedecer a quien integra.
      const enArranque = PoliticaDeNotificaciones();
      expect(decidir(politica: enArranque, disparador: Disparador.laAppLoPidio),
          AccionDePermiso.pedirAlSistema);
    });

    test('la pregunta blanda va antes que el diálogo del sistema', () {
      const blanda = PoliticaDeNotificaciones(preguntaBlanda: true);
      expect(decidir(politica: blanda), AccionDePermiso.mostrarPreguntaBlanda);
    });

    test('a quien dijo «ahora no» se le respeta la espera', () {
      const cada7 = PoliticaDeNotificaciones(reintentarCadaDias: 7);
      expect(
        decidir(politica: cada7, yaSePregunto: true, desde: const Duration(days: 2)),
        AccionDePermiso.ninguna,
      );
      expect(
        decidir(politica: cada7, yaSePregunto: true, desde: const Duration(days: 9)),
        AccionDePermiso.pedirAlSistema,
      );
    });

    test('pero si la app lo pide, la espera no aplica', () {
      const cada7 = PoliticaDeNotificaciones(reintentarCadaDias: 7);
      expect(
        decidir(
          politica: cada7,
          disparador: Disparador.laAppLoPidio,
          yaSePregunto: true,
          desde: const Duration(days: 1),
        ),
        AccionDePermiso.pedirAlSistema,
      );
    });

    test('espera cero: se pregunta en cada arranque', () {
      const sinEspera = PoliticaDeNotificaciones(reintentarCadaDias: 0);
      expect(
        decidir(politica: sinEspera, yaSePregunto: true, desde: const Duration(minutes: 1)),
        AccionDePermiso.pedirAlSistema,
      );
    });
  });
}
