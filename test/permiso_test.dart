import 'package:hz_collection_sdk/src/permiso.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mensajeria_falsa.dart';

void main() {
  group('EstadoDelPermiso', () {
    test('sólo se vuelve a preguntar donde el diálogo todavía existe', () {
      for (final e in [
        EstadoDelPermiso.sinPreguntar,
        EstadoDelPermiso.denegado,
        EstadoDelPermiso.provisional,
      ]) {
        expect(e.puedeVolverAPreguntarse, isTrue, reason: e.name);
      }

      for (final e in [
        EstadoDelPermiso.concedido,
        EstadoDelPermiso.denegadoParaSiempre,
      ]) {
        expect(e.puedeVolverAPreguntarse, isFalse, reason: e.name);
      }
    });

    test('provisional recibe avisos, aunque en silencio', () {
      expect(EstadoDelPermiso.provisional.permiteRecibir, isTrue);
      expect(EstadoDelPermiso.concedido.permiteRecibir, isTrue);

      for (final e in [
        EstadoDelPermiso.sinPreguntar,
        EstadoDelPermiso.denegado,
        EstadoDelPermiso.denegadoParaSiempre,
      ]) {
        expect(e.permiteRecibir, isFalse, reason: e.name);
      }
    });

    test('los Ajustes son el último recurso, no el opuesto de preguntar', () {
      expect(EstadoDelPermiso.denegadoParaSiempre.soloQuedanLosAjustes, isTrue);

      // Concedido tampoco admite diálogo, y sin embargo no hay nada que ir a
      // arreglar a los Ajustes. Por eso son dos preguntas y no una negada.
      expect(EstadoDelPermiso.concedido.soloQuedanLosAjustes, isFalse);
      expect(EstadoDelPermiso.denegado.soloQuedanLosAjustes, isFalse);
    });
  });

  group('GestorDePermiso lee sin gastar el diálogo', () {
    test('preguntar por el estado NO muestra ningún diálogo', () async {
      // Es la razón de ser de todo el archivo: `estadoActual()` se llama en
      // cada vuelta del segundo plano, y si esa llamada gastara el diálogo el
      // permiso quedaría quemado antes de que la aplicación pudiera explicar
      // para qué sirve.
      final fcm = MensajeriaFalsa(estado: AuthorizationStatus.notDetermined);
      final gestor = GestorDePermiso(mensajeria: fcm);

      await gestor.estadoActual();
      await gestor.estadoActual();

      expect(fcm.lecturas, 2);
      expect(fcm.dialogos, 0);
    });

    test('cada respuesta del sistema conserva lo que habilita o cierra',
        () async {
      final esperado = {
        AuthorizationStatus.authorized: EstadoDelPermiso.concedido,
        AuthorizationStatus.provisional: EstadoDelPermiso.provisional,
        AuthorizationStatus.notDetermined: EstadoDelPermiso.sinPreguntar,
        AuthorizationStatus.deniedPermanently:
            EstadoDelPermiso.denegadoParaSiempre,
      };

      for (final par in esperado.entries) {
        final gestor =
            GestorDePermiso(mensajeria: MensajeriaFalsa(estado: par.key));
        expect(await gestor.estadoActual(), par.value, reason: par.key.name);
      }
    });

    test('donde no hay segunda oportunidad, un «no» es para siempre', () async {
      // `denied` a secas es el «no» crudo, y no significa lo mismo en todos
      // lados: sólo Android 13+ admite otro diálogo después. Esta prueba corre
      // en la máquina de escritorio, que entra por la MISMA rama que iPhone
      // —no es Android—, y ahí Firebase reporta el «no» definitivo como
      // `denied` a secas. Tomarlo literal dejaría a la aplicación ofreciendo
      // para siempre un botón que ya no puede mostrar nada.
      final gestor = GestorDePermiso(
        mensajeria: MensajeriaFalsa(estado: AuthorizationStatus.denied),
      );

      final estado = await gestor.estadoActual();
      expect(estado, EstadoDelPermiso.denegadoParaSiempre);
      expect(estado.puedeVolverAPreguntarse, isFalse);
      expect(estado.soloQuedanLosAjustes, isTrue);
    });

    test('no poder leer no es tener la puerta cerrada', () async {
      // Contestar «denegado para siempre» sin saberlo mandaría a la persona a
      // los Ajustes a arreglar un problema que no es suyo. `sinPreguntar` es el
      // único estado que no cierra ningún camino.
      final gestor = GestorDePermiso(
        mensajeria: MensajeriaFalsa(rompeAlLeer: Exception('canal caído')),
      );

      final estado = await gestor.estadoActual();
      expect(estado, EstadoDelPermiso.sinPreguntar);
      expect(estado.puedeVolverAPreguntarse, isTrue);
    });
  });

  group('GestorDePermiso.pedir', () {
    test('el diálogo se dispara sólo cuando alguien lo pide', () async {
      final fcm = MensajeriaFalsa(
        estado: AuthorizationStatus.notDetermined,
        respuestaDelDialogo: AuthorizationStatus.authorized,
      );
      final gestor = GestorDePermiso(mensajeria: fcm);

      expect(await gestor.pedir(), EstadoDelPermiso.concedido);
      expect(fcm.dialogos, 1);
      // Y lo que quedó es lo que se lee después: pedir no deja al SDK creyendo
      // una cosa y al sistema otra.
      expect(await gestor.estadoActual(), EstadoDelPermiso.concedido);
    });

    test('pedir cuando ya no hay diálogo devuelve el «no», no un «sí»',
        () async {
      // En Android, pedir con el permiso ya denegado para siempre no muestra
      // nada y devuelve el mismo estado. Si esto devolviera otra cosa, la
      // aplicación mostraría su pantalla de éxito sobre un permiso que sigue
      // cerrado.
      final gestor = GestorDePermiso(
        mensajeria:
            MensajeriaFalsa(estado: AuthorizationStatus.deniedPermanently),
      );

      expect(await gestor.pedir(), EstadoDelPermiso.denegadoParaSiempre);
    });

    test('un diálogo que no llegó a mostrarse no gastó nada', () async {
      // Si el canal nativo falla, la persona no vio ninguna pregunta: el estado
      // real sigue siendo el que había, y contestar «denegado» ahí quemaría en
      // los papeles una oportunidad que en el teléfono sigue entera.
      final fcm = MensajeriaFalsa(
        estado: AuthorizationStatus.notDetermined,
        rompeAlPedir: Exception('el canal nativo no contestó'),
      );
      final gestor = GestorDePermiso(mensajeria: fcm);

      final estado = await gestor.pedir();
      expect(estado, EstadoDelPermiso.sinPreguntar);
      expect(estado.puedeVolverAPreguntarse, isTrue);
      expect(fcm.lecturas, 1, reason: 'tuvo que releer el estado real');
    });
  });

  group('GestorDePermiso.abrirAjustes', () {
    test('devuelve si se pudo abrir, no si la persona activó algo', () async {
      final gestor = GestorDePermiso(abridorDeAjustes: () async => true);
      expect(await gestor.abrirAjustes(), isTrue);
    });

    test('un teléfono que no deja abrirlos no tumba a la aplicación', () async {
      final gestor = GestorDePermiso(
        abridorDeAjustes: () async => throw Exception('capa del fabricante'),
      );
      expect(await gestor.abrirAjustes(), isFalse);
    });

    test('abrir los Ajustes no toca la mensajería', () async {
      // Son dos paquetes pero una sola autoridad: el estado lo dicta siempre
      // Firebase. Si abrir los Ajustes preguntara algo por el otro camino,
      // habría dos respuestas y ninguna forma de saber a cuál creerle.
      final fcm = MensajeriaFalsa();
      final gestor = GestorDePermiso(
        mensajeria: fcm,
        abridorDeAjustes: () async => true,
      );

      await gestor.abrirAjustes();
      expect(fcm.lecturas, 0);
      expect(fcm.dialogos, 0);
    });
  });
}
