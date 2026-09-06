/// LA COLA DE EVENTOS — lo que se midió y todavía no salió del teléfono.
///
/// ══ POR QUÉ HAY UNA COLA Y NO UN ENVÍO ══
///
/// La regla de la política es que **nunca se transmite en el mismo momento de medir**. Un
/// formulario de ocho campos genera unos veinte eventos; mandarlos de a uno serían veinte
/// peticiones HTTP mientras la persona escribe, cada una levantando la radio del teléfono.
/// Eso se nota en la batería y se nota en la pantalla. Se escriben en el disco —que es
/// barato— y salen todos juntos en la próxima apertura.
///
/// ══ POR QUÉ SOBREVIVE AL CIERRE DE LA APLICACIÓN, Y TIENE QUE HACERLO ══
///
/// El evento más caro de perder es justamente el último: `SESION_CIERRA`, que es el que dice
/// cuánto duró la sesión. Si la cola viviera en memoria, ese evento no existiría nunca —
/// la aplicación se está cerrando cuando ocurre—. Vive en `SharedPreferences` por la misma
/// razón que el resto del estado del SDK: es lo único que cruza el cierre y el aislado de
/// segundo plano.
///
/// ══ 🔴 LO QUE ESTA CLASE PROMETE, Y ES LO MÁS IMPORTANTE DE ELLA ══
///
/// **Nunca lanza.** Ni al encolar, ni al leer, ni al borrar. Todo está envuelto y todo
/// devuelve un valor razonable si falla. Una medición perdida es un problema; una
/// aplicación que no abre porque el almacenamiento del teléfono está lleno es otro tamaño
/// de problema, y no se paga por un dato de segmentación.
library;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../transmision/politica_de_transmision.dart';
import 'evento.dart';

class ColaDeEventos {
  ColaDeEventos({this.politica = PoliticaDeTransmision.porOmision});

  final PoliticaDeTransmision politica;

  static const _claveCola = 'akpush.comportamiento.cola';
  static const _claveSeq = 'akpush.comportamiento.seq';
  static const _claveDescartados = 'akpush.comportamiento.descartados';

  /// 🔴 UN CANDADO, PORQUE `SharedPreferences` NO ES ATÓMICO DESDE DOS LADOS.
  ///
  /// Leer-modificar-escribir con dos `await` en el medio es una carrera: dos eventos que se
  /// encolan casi a la vez —y pasa, porque un campo que pierde el foco mientras se envía el
  /// formulario dispara dos— leen la misma lista y el segundo pisa al primero. El evento no
  /// da error: desaparece. Se serializa todo por acá.
  static Future<void> _turno = Future<void>.value();

  static Future<T> _enFila<T>(Future<T> Function() hacer) {
    final completador = Completer<T>();
    _turno = _turno.then((_) async {
      try {
        completador.complete(await hacer());
      } catch (e, s) {
        completador.completeError(e, s);
      }
    });
    return completador.future;
  }

  /// Guarda un evento. **Nunca lanza y nunca demora al que la llama**: quien mide sigue
  /// con lo suyo.
  Future<void> encolar(EventoDeComportamiento evento) => _enFila(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final lista = _leerCrudo(prefs);
          lista.add(jsonEncode(evento.aDisco()));
          final descartados = _podar(lista);
          await prefs.setStringList(_claveCola, lista);
          if (descartados > 0) {
            await prefs.setInt(_claveDescartados,
                (prefs.getInt(_claveDescartados) ?? 0) + descartados);
          }
        } catch (_) {
          // A propósito. Ver la cabecera: perder un evento cuesta un dato.
        }
      });

  /// El próximo número de secuencia. Sólo crece, y sobrevive al cierre.
  ///
  /// Sirve para dos cosas que no se pueden hacer sin él: borrar de la cola **exactamente**
  /// lo que se mandó —y no lo que se encoló mientras se mandaba—, y que el servicio pueda
  /// reconocer un lote repetido cuando la respuesta se perdió pero el envío llegó.
  Future<int> proximoSeq() => _enFila(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final n = (prefs.getInt(_claveSeq) ?? 0) + 1;
          await prefs.setInt(_claveSeq, n);
          return n;
        } catch (_) {
          // Sin disco, un número que al menos no se repite dentro de esta sesión.
          return DateTime.now().microsecondsSinceEpoch;
        }
      });

  /// Todo lo que hay, en orden. Las líneas que no se entienden se saltean — ver
  /// [EventoDeComportamiento.deDisco].
  Future<List<EventoDeComportamiento>> leer() => _enFila(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          return _leerCrudo(prefs)
              .map((l) {
                try {
                  return EventoDeComportamiento.deDisco(jsonDecode(l));
                } catch (_) {
                  return null;
                }
              })
              .whereType<EventoDeComportamiento>()
              .toList();
        } catch (_) {
          return <EventoDeComportamiento>[];
        }
      });

  /// Borra los que ya salieron, y **sólo ésos**.
  ///
  /// 🔴 No es un `clear()` ni un «borrá hasta el número tal», y la diferencia importa dos
  /// veces. Primero, entre que sale la petición y vuelve la respuesta pasan cientos de
  /// milisegundos, y en ese rato la persona puede haber tocado un campo: un borrado por
  /// rango se llevaría ese evento nuevo, que nunca se mandó. Y segundo, la cola se manda en
  /// varios lotes cuando hay dos personas o mucha acumulación, así que los números que
  /// salieron **no** son un rango contiguo.
  Future<void> quitarLos(Set<int> seqs) => _enFila(() async {
        if (seqs.isEmpty) return;
        try {
          final prefs = await SharedPreferences.getInstance();
          final quedan = _leerCrudo(prefs).where((l) {
            try {
              final q = (jsonDecode(l) as Map)['q'];
              return q is! num || !seqs.contains(q.toInt());
            } catch (_) {
              // Una línea ilegible no se puede comparar. Se la lleva igual: dejarla ahí
              // para siempre haría crecer la cola sin que nadie pueda vaciarla.
              return false;
            }
          }).toList();
          await prefs.setStringList(_claveCola, quedan);
        } catch (_) {}
      });

  /// Cuántos eventos se perdieron por desborde desde la última vez que se preguntó, y
  /// pone el contador en cero.
  ///
  /// Se lee una sola vez y viaja en el `datos` del siguiente `SESION_ABRE`: así del otro
  /// lado se sabe que hay un hueco y de qué tamaño, en vez de tener que deducirlo de una
  /// serie que salta.
  Future<int> tomarDescartados() => _enFila(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final n = prefs.getInt(_claveDescartados) ?? 0;
          if (n > 0) await prefs.setInt(_claveDescartados, 0);
          return n;
        } catch (_) {
          return 0;
        }
      });

  /// Cuántos se descartaron y todavía no se avisaron, **sin poner el contador en cero**.
  /// Es para mirar; el que consume es [tomarDescartados].
  Future<int> cuantosDescartados() => _enFila(() async {
        try {
          return (await SharedPreferences.getInstance())
                  .getInt(_claveDescartados) ??
              0;
        } catch (_) {
          return 0;
        }
      });

  /// Cuántos hay esperando. Para el diagnóstico y para la pantalla.
  Future<int> cuantos() => _enFila(() async {
        try {
          return _leerCrudo(await SharedPreferences.getInstance()).length;
        } catch (_) {
          return 0;
        }
      });

  List<String> _leerCrudo(SharedPreferences prefs) =>
      List<String>.from(prefs.getStringList(_claveCola) ?? const <String>[]);

  /// Aplica los dos topes y devuelve cuántos se descartaron. Modifica la lista en el lugar.
  ///
  /// Se aplica el de bytes también, y no sólo el de eventos, porque un evento no tiene
  /// tamaño fijo: el nombre de un formulario largo o un `datos` que crezca mañana harían que
  /// mil eventos pesen mucho más de lo previsto. El freno tiene que estar donde está el
  /// daño, que es el archivo, no la cuenta.
  int _podar(List<String> lista) {
    var descartados = 0;
    while (lista.length > politica.topeDeEventos) {
      lista.removeAt(0);
      descartados++;
    }
    var bytes = lista.fold<int>(0, (a, l) => a + l.length);
    while (bytes > politica.topeDeBytes && lista.length > 1) {
      bytes -= lista.removeAt(0).length;
      descartados++;
    }
    return descartados;
  }
}
