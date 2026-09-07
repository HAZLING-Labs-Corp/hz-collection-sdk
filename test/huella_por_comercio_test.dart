import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hz_collection_sdk/src/transmision/huella_local.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('la huella de lo ya transmitido es POR COMERCIO', () {
    test('🔴 lo mandado a un comercio no cuenta como mandado en el otro', () async {
      // Es el defecto de fondo, medido el 2026-09-06: el teléfono mandó sus ~125 señales a un
      // comercio, anotó «ya las mandé», se cambió a otro que del otro lado NO TENÍA NADA, y la
      // política concluyó «no cambió nada» y no mandó. Esa persona quedó con 18 señales para
      // siempre y los tres motores no pudieron concluir nada sobre ella.
      const rodar = HuellaLocal(comercio: 'rodar');
      const mundo = HuellaLocal(comercio: 'mundototal');

      await rodar.anotar('senales', {'hd_marca': 'samsung', 'ent_avisos': 'true'}, fueResincronizacion: false);

      expect((await rodar.leer('senales')).isNotEmpty, isTrue,
          reason: 'el comercio al que sí se le mandó tiene que recordarlo');
      expect((await mundo.leer('senales')).isEmpty, isTrue,
          reason: 'el otro NO puede creer que ya recibió lo que nunca recibió');
    });

    test('volver al comercio anterior NO retransmite lo que ese comercio ya tiene', () async {
      // Por esto la clave lleva el comercio en vez de borrarse al cambiar: borrar arreglaría el
      // defecto, pero con dos comercios en uso alternado cada cambio pagaría un barrido completo.
      const rodar = HuellaLocal(comercio: 'rodar');
      await rodar.anotar('senales', {'hd_marca': 'samsung'}, fueResincronizacion: false);
      await const HuellaLocal(comercio: 'mundototal').anotar('senales', {'hd_marca': 'samsung'}, fueResincronizacion: false);

      expect((await rodar.leer('senales')).isNotEmpty, isTrue);
    });

    test('olvidar uno no borra el del otro', () async {
      const rodar = HuellaLocal(comercio: 'rodar');
      const mundo = HuellaLocal(comercio: 'mundototal');
      await rodar.anotar('senales', {'a': '1'}, fueResincronizacion: false);
      await mundo.anotar('senales', {'a': '1'}, fueResincronizacion: false);

      await rodar.olvidar('senales');

      expect((await rodar.leer('senales')).isEmpty, isTrue);
      expect((await mundo.leer('senales')).isNotEmpty, isTrue);
    });

    test('sin comercio conserva la clave vieja, así nada se rompe al actualizar', () async {
      // Un SDK que todavía no pase el comercio tiene que comportarse igual que antes.
      const sinComercio = HuellaLocal();
      await sinComercio.anotar('senales', {'a': '1'}, fueResincronizacion: false);
      expect((await sinComercio.leer('senales')).isNotEmpty, isTrue);
      expect((await const HuellaLocal(comercio: 'rodar').leer('senales')).isEmpty, isTrue);
    });
  });
}
