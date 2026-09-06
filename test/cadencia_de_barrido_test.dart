import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/src/transmision/cadencia_de_barrido.dart';

void main() {
  final ahora = DateTime.utc(2026, 9, 6, 20, 0);

  group('cuándo toca volver a medir el aparato', () {
    test('si nunca se midió, toca siempre', () {
      expect(
        tocaRemedir(ahora: ahora, ultimoBarrido: null, camposDelUltimoBarrido: 0),
        isTrue,
      );
    });

    test('recién medido y completo: no toca', () {
      expect(
        tocaRemedir(
          ahora: ahora,
          ultimoBarrido: ahora.subtract(const Duration(minutes: 2)),
          camposDelUltimoBarrido: 127,
        ),
        isFalse,
        reason: 'volver a la aplicación diez veces en un minuto no puede gastar diez barridos',
      );
    });

    test('completo y viejo: toca a los quince minutos', () {
      DateTime hace(int m) => ahora.subtract(Duration(minutes: m));
      expect(tocaRemedir(ahora: ahora, ultimoBarrido: hace(14), camposDelUltimoBarrido: 127), isFalse);
      expect(tocaRemedir(ahora: ahora, ultimoBarrido: hace(15), camposDelUltimoBarrido: 127), isTrue);
    });

    test('🔴 corto y reciente: toca al minuto, no a los quince', () {
      // Es el caso que originó todo esto: dos personas quedaron con las 18 señales del bloque
      // básico PARA SIEMPRE porque el barrido se cortó y no había segunda oportunidad. Un
      // barrido corto no es un estado válido que haya que respetar: es un accidente.
      final hace2 = ahora.subtract(const Duration(minutes: 2));
      expect(tocaRemedir(ahora: ahora, ultimoBarrido: hace2, camposDelUltimoBarrido: 18), isTrue);
      expect(
        tocaRemedir(ahora: ahora, ultimoBarrido: hace2, camposDelUltimoBarrido: 127),
        isFalse,
        reason: 'el mismo tiempo con un barrido completo NO tiene que reintentar',
      );
    });

    test('corto y muy reciente: tampoco se reintenta a lo loco', () {
      expect(
        tocaRemedir(
          ahora: ahora,
          ultimoBarrido: ahora.subtract(const Duration(seconds: 30)),
          camposDelUltimoBarrido: 18,
        ),
        isFalse,
      );
    });

    test('el corte deja pasar lo básico y no castiga a un iPhone', () {
      // Android entrega ~125 campos; iOS ~33 por límite de plataforma, no por fallo. El corte
      // tiene que quedar por arriba del bloque básico (18) y por debajo de lo que da un iPhone.
      expect(camposQueDelatanUnBarridoCorto, greaterThan(18));
      expect(camposQueDelatanUnBarridoCorto, lessThan(100));
    });

    test('reintentar es más seguido que remedir, o el corte no serviría de nada', () {
      expect(cadaCuantoSeReintenta, lessThan(cadaCuantoSeRemide));
    });
  });
}
