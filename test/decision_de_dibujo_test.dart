import 'package:hz_collection_sdk/src/decision_de_dibujo.dart';
import 'package:hz_collection_sdk/src/push_message.dart';
import 'package:flutter_test/flutter_test.dart';

const _aviso = PushMessage(data: {'pushLogId': '6a94'}, title: 'Hola');

void main() {
  group('PorteroDeDibujo', () {
    test('sin callback registrado se dibuja, como venía siendo', () async {
      expect(await PorteroDeDibujo().resolver(_aviso), DecisionDeDibujo.mostrar);
    });

    test('respeta lo que contesta la aplicación', () async {
      final portero = PorteroDeDibujo(
        alDecidir: (_) => DecisionDeDibujo.noMostrar,
      );
      expect(await portero.resolver(_aviso), DecisionDeDibujo.noMostrar);
    });

    test('un callback que revienta no le cuesta el aviso a la persona', () async {
      final sincronico = PorteroDeDibujo(
        alDecidir: (_) => throw StateError('la pantalla no estaba montada'),
      );
      expect(await sincronico.resolver(_aviso), DecisionDeDibujo.mostrar);

      final asincronico = PorteroDeDibujo(
        alDecidir: (_) async => throw StateError('se cayó la consulta'),
      );
      expect(await asincronico.resolver(_aviso), DecisionDeDibujo.mostrar);
    });

    test('si tarda más del límite se muestra y no se espera más', () async {
      final portero = PorteroDeDibujo(
        limite: const Duration(milliseconds: 10),
        alDecidir: (_) async {
          await Future<void>.delayed(const Duration(seconds: 2));
          return DecisionDeDibujo.noMostrar;
        },
      );

      final reloj = Stopwatch()..start();
      final decision = await portero.resolver(_aviso);
      reloj.stop();

      expect(decision, DecisionDeDibujo.mostrar);
      expect(reloj.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('el silencioso se dibuja, pero sin ruido', () {
      expect(DecisionDeDibujo.mostrarSilencioso.seDibuja, isTrue);
      expect(DecisionDeDibujo.mostrarSilencioso.sinRuido, isTrue);
      expect(DecisionDeDibujo.mostrar.sinRuido, isFalse);
      expect(DecisionDeDibujo.noMostrar.seDibuja, isFalse);
    });

    test('el que tarda y ADEMÁS se rompe no deja un error suelto', () async {
      // La combinación que más cuesta encontrar a mano: el callback se pasa del
      // límite —ya se decidió mostrar y nadie espera su respuesta— y recién
      // después revienta. Ese error no tiene dueño; si se escapara, tumbaría el
      // manejador de llegada de FCM entero, un rato después y sin relación
      // visible con el aviso que lo causó.
      final portero = PorteroDeDibujo(
        limite: const Duration(milliseconds: 10),
        alDecidir: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          throw StateError('se cayó tarde');
        },
      );

      expect(await portero.resolver(_aviso), DecisionDeDibujo.mostrar);
      // Se espera de más a propósito: si el error escapara, aparecería acá y la
      // prueba fallaría con él, que es exactamente lo que se quiere detectar.
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });

    test('la opinión se puede cambiar y sacar en caliente', () async {
      // El callback se lee en cada aviso y no se copia al construir: una app
      // que lo cambia al entrar a una pantalla y lo saca al salir tiene que ver
      // el efecto en el aviso siguiente, no en el próximo arranque.
      final portero = PorteroDeDibujo();
      expect(await portero.resolver(_aviso), DecisionDeDibujo.mostrar);

      portero.alDecidir = (_) => DecisionDeDibujo.noMostrar;
      expect(await portero.resolver(_aviso), DecisionDeDibujo.noMostrar);

      portero.alDecidir = null;
      expect(await portero.resolver(_aviso), DecisionDeDibujo.mostrar);
    });
  });

  group('la decisión no toca lo que se mide', () {
    test('el aviso que se le muestra al callback es el mismo que llega',
        () async {
      // Preguntar no puede consumir ni recortar nada: lo que después sale por
      // onMessage y lo que se reporta como entregado se arman con este mismo
      // objeto. Si el portero entregara una copia recortada, el `pushLogId`
      // podría perderse en el camino y el envío quedaría sin medir.
      PushMessage? visto;
      final portero = PorteroDeDibujo(alDecidir: (m) {
        visto = m;
        return DecisionDeDibujo.noMostrar;
      });

      await portero.resolver(_aviso);

      expect(identical(visto, _aviso), isTrue);
      expect(_aviso.pushLogId, '6a94');
    });

    test('ninguna de las tres opciones apaga la medición', () async {
      // 🔴 Guardarraíl de contrato. Las tres hablan SÓLO del dibujo: la entrega
      // se reporta igual con las tres, porque el aviso llegó al teléfono y que
      // la app decida no dibujarlo es posterior a la entrega. El día que
      // alguien agregue un cuarto valor con el sentido de «tampoco lo cuentes»,
      // esta prueba se cae y obliga a discutirlo — sin ella, el comercio que
      // MÁS cuida a su gente pasa a ser el que peor mide, y nadie lo nota.
      expect(DecisionDeDibujo.values, hasLength(3));

      for (final decision in DecisionDeDibujo.values) {
        final portero = PorteroDeDibujo(alDecidir: (_) => decision);
        expect(await portero.resolver(_aviso), decision, reason: decision.name);
        // El único eje que existe es el del dibujo: se dibuja o no, y con ruido
        // o sin él. No hay ningún tercer eje que hable de reportar.
        expect(decision.sinRuido, decision == DecisionDeDibujo.mostrarSilencioso);
        expect(decision.seDibuja, decision != DecisionDeDibujo.noMostrar);
      }
    });
  });
}
