/// CUÁNTO TARDA CADA COSA DEL RASTREO, Y EN QUÉ HILO — la evidencia de que nada pesado
/// bloquea el hilo principal.
///
/// ══ POR QUÉ IMPORTA MÁS DE LO QUE PARECE ══
///
/// Desde Flutter 3.29 el isolate de Dart corre en el MISMO hilo que el principal de Android
/// y de iOS (hilos fusionados). Todo lo que Dart haga de corrido, sin `await`, es tiempo en
/// que Android no atiende un toque: cinco segundos así son un ANR. Y al revés: un
/// `MethodChannel` que hace algo lento en el principal (el Keystore) congela a Dart.
///
/// Se miden dos cosas distintas, y no se mezclan:
///  · [sincrono] — trabajo de Dart de corrido. ESE tiempo es bloqueo del hilo principal.
///  · [asincrono] — una operación con `await` (SQLite, la firma nativa). Su tiempo total NO
///    es bloqueo: mientras espera, el hilo atiende otras cosas. Se mide para saber cuánto
///    tarda, no para culparla.
///
/// Por omisión está apagado y no cuesta nada más que un `if`. La app de diagnóstico lo
/// prende; cada medida sale por consola con el prefijo `HzRastreoHilo` (en Android llega a
/// logcat como `I flutter`), junto a la del lado nativo, que sale con la misma etiqueta.
library;

import 'dart:isolate';

class MedidorDeHilo {
  MedidorDeHilo._();

  /// Prendido, imprime cada medida y guarda el máximo por operación.
  static bool activo = false;

  static final Map<String, ({int veces, double maxMs, double totalMs, bool bloquea})> _por = {};

  static String get _isolate => Isolate.current.debugName ?? '?';

  /// Mide [f], que corre de corrido en este isolate: todo su tiempo es bloqueo.
  static T sincrono<T>(String que, T Function() f) {
    if (!activo) return f();
    final s = Stopwatch()..start();
    final r = f();
    _anotar(que, s.elapsedMicroseconds / 1000, bloquea: true);
    return r;
  }

  /// Mide [f] de punta a punta, con sus esperas: su tiempo NO es bloqueo del hilo.
  static Future<T> asincrono<T>(String que, Future<T> Function() f) async {
    if (!activo) return f();
    final s = Stopwatch()..start();
    try {
      return await f();
    } finally {
      _anotar(que, s.elapsedMicroseconds / 1000, bloquea: false);
    }
  }

  static void _anotar(String que, double ms, {required bool bloquea}) {
    final a = _por[que];
    _por[que] = (
      veces: (a?.veces ?? 0) + 1,
      maxMs: a == null || ms > a.maxMs ? ms : a.maxMs,
      totalMs: (a?.totalMs ?? 0) + ms,
      bloquea: bloquea,
    );
    // ignore: avoid_print
    print('HzRastreoHilo dart $que isolate=$_isolate '
        '${bloquea ? 'bloquea' : 'espera'}=${ms.toStringAsFixed(2)}ms');
  }

  /// El resumen: por operación, cuántas veces, el máximo, la media y si bloquea.
  static List<String> resumen() => [
        for (final e in _por.entries)
          '${e.key} · ${e.value.bloquea ? 'BLOQUEA' : 'espera'} · n=${e.value.veces} · '
              'máx=${e.value.maxMs.toStringAsFixed(2)}ms · '
              'media=${(e.value.totalMs / e.value.veces).toStringAsFixed(2)}ms',
      ];

  static void olvidar() => _por.clear();
}
