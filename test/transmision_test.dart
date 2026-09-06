/// LA POLÍTICA DE TRANSMISIÓN, PROBADA SIN TELÉFONO.
///
/// 🔴 Lo que de verdad se prueba acá es **la trampa de las señales de momento**. Es un
/// defecto que no da ningún síntoma: si las diez señales que cambian solas entran en la
/// comparación, el delta nunca está vacío, todo se transmite siempre, y el sistema parece
/// andar perfecto. Sólo se nota en la factura. Una prueba es la única forma de que alguien
/// se entere el mismo día.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/src/transmision/politica_de_transmision.dart';

void main() {
  final ahora = DateTime(2026, 9, 4, 22);
  final ayer = ahora.subtract(const Duration(days: 1));

  group('las señales de momento', () {
    test('son exactamente las diez que declara el back, ni una más ni una menos', () {
      // 🔴 ESTA PRUEBA ES UNA SEGUNDA LISTA VIGILADA, no una redundancia. La lista de
      // verdad vive en `SENALES_DE_MOMENTO` de `escritura-a-destino.service.ts`; acá está
      // copiada porque Dart no puede leer un `const` de TypeScript. Si alguien agrega una
      // señal de momento de un solo lado, esto falla y obliga a mirar el otro.
      expect(senalesDeMomento, {
        'hd_hora_local',
        'hd_dia_de_semana',
        'ent_pantalla_encendida',
        'ent_nivel_de_senal',
        'bat_temperatura_decimas_c',
        'bat_voltaje_mv',
        'red_bajada_kbps',
        'red_subida_kbps',
        'cfg_boot_count',
        'ubicacion_cuando',
      });
    });

    test('🔴 los dos que el back todavía no tiene están aparte, no mezclados', () {
      // La lista de arriba es la copia literal del back y se compara nombre por nombre. Si
      // alguien mete acá adentro los que encontró este lado, esa comparación deja de servir
      // para lo único que sirve: avisar que las dos listas se separaron.
      expect(momentosQueElBackTodaviaNoTiene, {'hd_ram_libre_mb', 'hd_ram_en_las_ultimas'});
      for (final n in momentosQueElBackTodaviaNoTiene) {
        expect(senalesDeMomento, isNot(contains(n)));
      }
      // Pero el módulo `senales` los ignora igual: es lo que hace que el delta sirva hoy.
      expect(senalesDeMomentoDe('senales'), containsAll(momentosQueElBackTodaviaNoTiene));
    });

    test('un cambio SÓLO en la memoria libre no dispara nada', () {
      // Medido el 2026-09-04 en el emulador: era el único campo que se movía entre sesiones,
      // y bastaba para transmitir las 105 señales enteras en cada apertura.
      final d = decidirEnvio(
        modulo: 'senales',
        medido: const {'hd_marca': 'Xiaomi', 'hd_ram_libre_mb': 1280},
        huellaAnterior: huellaDe(const {'hd_marca': 'Xiaomi', 'hd_ram_libre_mb': 1536}),
        ultimaResincronizacion: DateTime(2026, 9, 4, 21),
        ahora: DateTime(2026, 9, 4, 22),
      );
      expect(d.mandar, isFalse);
    });

    test('cada módulo tiene la suya, y `autenticidad` no tiene ninguna', () {
      expect(senalesDeMomentoDe('senales'), containsAll(senalesDeMomento));
      expect(senalesDeMomentoDe('aparato'), contains('bateria'));
      // Los cinco booleanos de autenticidad no se mueven solos: si alguno cambia, cambió
      // algo de verdad y hay que enterarse.
      expect(senalesDeMomentoDe('autenticidad'), isEmpty);
      expect(senalesDeMomentoDe('loQueSea'), isEmpty);
    });

    test('el tipo de red del aparato NO es un momento', () {
      // Pasar de wifi a datos es un cambio real y un envío por eso informa algo. Si
      // entrara en la lista, ese cambio no se enteraría nunca.
      expect(senalesDeMomentoDe('aparato'), isNot(contains('red')));
      expect(senalesDeMomentoDe('aparato'), isNot(contains('espacioTotalMb')));
    });
  });

  group('decidirEnvio', () {
    DecisionDeEnvio decidir({
      required Map<String, Object?> medido,
      Map<String, Object?> anterior = const {},
      DateTime? resync,
      String modulo = 'senales',
      PoliticaDeTransmision politica = PoliticaDeTransmision.porOmision,
    }) =>
        decidirEnvio(
          modulo: modulo,
          medido: medido,
          huellaAnterior: huellaDe(anterior),
          ultimaResincronizacion: resync ?? ayer,
          ahora: ahora,
          politica: politica,
        );

    test('la primera medición siempre sale: no hay con qué compararla', () {
      final d = decidir(medido: {'hd_marca': 'Xiaomi'});
      expect(d.mandar, isTrue);
      expect(d.porQue, contains('primera medición'));
    });

    test('🔴 la trampa: si sólo cambiaron los momentos, NO se transmite', () {
      // Es el caso exacto que hace que todo el mecanismo sirva o no sirva. Mismo teléfono,
      // misma configuración, un minuto después: la hora, el voltaje y la temperatura
      // cambiaron y nada más.
      final antes = <String, Object?>{
        'hd_marca': 'Xiaomi',
        'cfg_adb_enabled': 0,
        'hd_hora_local': 21,
        'bat_voltaje_mv': 4012,
        'bat_temperatura_decimas_c': 281,
        'red_bajada_kbps': 12000,
      };
      final ahoraMedido = <String, Object?>{
        ...antes,
        'hd_hora_local': 22,
        'bat_voltaje_mv': 3987,
        'bat_temperatura_decimas_c': 305,
        'red_bajada_kbps': 9500,
      };
      final d = decidir(medido: ahoraMedido, anterior: antes);
      expect(d.mandar, isFalse, reason: 'los momentos no pueden disparar un envío');
      expect(d.porQue, contains('nada cambió'));
    });

    test('un cambio de verdad sí lo dispara, y dice cuál', () {
      final d = decidir(
        medido: {'hd_marca': 'Xiaomi', 'cfg_adb_enabled': 1, 'hd_hora_local': 22},
        anterior: {'hd_marca': 'Xiaomi', 'cfg_adb_enabled': 0, 'hd_hora_local': 3},
      );
      expect(d.mandar, isTrue);
      expect(d.camposQueCambiaron, ['cfg_adb_enabled']);
      // La hora cambió de las 3 a las 22 y no cuenta. Si contara, esta prueba no probaría
      // nada: pasaría igual con el mecanismo roto.
      expect(d.camposQueCambiaron, isNot(contains('hd_hora_local')));
    });

    test('un campo que DESAPARECIÓ también es un cambio', () {
      // Que el teléfono deje de devolver algo dice tanto como que lo cambie: el fabricante
      // lo cerró, o el sistema se actualizó. Sin esta vuelta la huella lo daría por
      // vigente para siempre.
      final d = decidir(
        medido: {'hd_marca': 'Xiaomi'},
        anterior: {'hd_marca': 'Xiaomi', 'acc_activos': 2},
      );
      expect(d.mandar, isTrue);
      expect(d.camposQueCambiaron, ['acc_activos']);
    });

    test('a los siete días se resincroniza aunque no haya cambiado nada', () {
      final d = decidir(
        medido: {'hd_marca': 'Xiaomi'},
        anterior: {'hd_marca': 'Xiaomi'},
        resync: ahora.subtract(const Duration(days: 7)),
      );
      expect(d.mandar, isTrue);
      expect(d.porQue, contains('resincronización'));
    });

    test('a los seis días todavía no', () {
      final d = decidir(
        medido: {'hd_marca': 'Xiaomi'},
        anterior: {'hd_marca': 'Xiaomi'},
        resync: ahora.subtract(const Duration(days: 6)),
      );
      expect(d.mandar, isFalse);
    });

    test('sin fecha de resincronización se manda: no hay constancia de que llegara nada', () {
      final d = decidirEnvio(
        modulo: 'senales',
        medido: const {'hd_marca': 'Xiaomi'},
        huellaAnterior: huellaDe(const {'hd_marca': 'Xiaomi'}),
        ultimaResincronizacion: null,
        ahora: ahora,
      );
      expect(d.mandar, isTrue);
    });

    test('`comoEstabaAntes` devuelve el comportamiento viejo: manda siempre', () {
      // Es la garantía de que traer la política no le cambia el comportamiento a nadie que
      // no la quiera. Sin esta salida, «aditivo» sería una promesa sin puerta.
      final d = decidir(
        medido: {'hd_marca': 'Xiaomi'},
        anterior: {'hd_marca': 'Xiaomi'},
        politica: PoliticaDeTransmision.comoEstabaAntes,
      );
      expect(d.mandar, isTrue);
    });

    test('una medición vacía no se manda: no hay nada que contar', () {
      expect(decidir(medido: {}).mandar, isFalse);
    });

    test('en `aparato`, que baje la batería no dispara nada; que cambie la red sí', () {
      final antes = <String, Object?>{
        'bateria': 88,
        'cargando': false,
        'espacioLibreMb': 12040,
        'red': ['wifi'],
        'sistema': 'android',
      };
      expect(
        decidir(
          modulo: 'aparato',
          anterior: antes,
          medido: {...antes, 'bateria': 61, 'espacioLibreMb': 11800},
        ).mandar,
        isFalse,
      );
      expect(
        decidir(
          modulo: 'aparato',
          anterior: antes,
          medido: {...antes, 'bateria': 61, 'red': ['mobile']},
        ).mandar,
        isTrue,
      );
    });
  });

  group('huellaDelValor', () {
    test('el mismo valor da la misma huella, y valores distintos dan huellas distintas', () {
      expect(huellaDelValor('Xiaomi'), huellaDelValor('Xiaomi'));
      expect(huellaDelValor('Xiaomi'), isNot(huellaDelValor('Samsung')));
      expect(huellaDelValor(1), isNot(huellaDelValor(2)));
    });

    test('el nulo NO se confunde con vacío ni con el texto «null»', () {
      // Si se confundieran, un campo que deja de venir se vería igual que uno que vino
      // vacío, y el cambio se perdería.
      expect(huellaDelValor(null), isNot(huellaDelValor('')));
      expect(huellaDelValor(null), isNot(huellaDelValor('null')));
    });

    test('es estable: el valor fijado acá no puede cambiar entre versiones', () {
      // 🔴 Si esto cambia, TODAS las huellas guardadas en TODOS los teléfonos dejan de
      // coincidir y el mundo entero retransmite una vez. No es catastrófico, pero tiene
      // que ser una decisión y no un accidente de refactorización.
      expect(huellaDelValor('Xiaomi'), 'a2c17f54');
    });
  });
}
