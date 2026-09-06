import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import 'modulo.dart';

/// EL REGISTRO — la única lista de módulos que existe.
///
/// La fachada le pide «arrancá», «entró alguien», «salió», y el registro se lo dice a todos.
/// **La fachada no nombra a ningún módulo**, y por eso agregar uno no la toca.
///
/// ══ QUÉ HACE ACÁ Y NO EN CADA MÓDULO ══
///
/// Tres cosas que si cada módulo resolviera por su cuenta, alguno la resolvería mal:
///
///  1. **Tragarse los fallos.** Un módulo que revienta no puede tumbar el arranque de la
///     aplicación ni impedir que corran los que siguen. Perder una medición cuesta un dato;
///     que falle el arranque cuesta que esa persona no reciba nada.
///  2. **Ponerle tope al tiempo.** Un try/catch no protege de algo que nunca termina. Sin
///     esto, un módulo colgado bloquea a todos los demás para siempre.
///  3. **Respetar lo que el comercio activó.** Un módulo apagado en la consola no corre, y
///     eso se decide en un solo lugar en vez de en cada uno.
class RegistroDeModulos {
  RegistroDeModulos(this._modulos);

  final List<Modulo> _modulos;

  /// 🔴 Ocho segundos por módulo y por gancho.
  ///
  /// El arranque de una aplicación tiene un presupuesto, y es la parte que la persona mira
  /// esperando. Con cuatro módulos y sin tope, uno que se cuelga contra un servidor caído
  /// deja la pantalla en blanco. Ocho alcanzan de sobra para una lectura local o una llamada
  /// que anda; lo que tarde más es que algo está mal, y entonces se lo saltea y se anota.
  static const _tope = Duration(seconds: 8);

  List<Modulo> get todos => List.unmodifiable(_modulos);

  /// Cuántos campos entregó el último barrido, sumando los módulos.
  ///
  /// Es lo que la fachada mira para saber si el barrido quedó corto y hay que reintentar antes
  /// de la cadencia normal. Se suma sobre TODOS y no sólo sobre los activos: un módulo que el
  /// comercio apagó entrega cero, y contarlo como corto haría reintentar para siempre algo que
  /// nunca va a traer nada.
  int get camposDelUltimoBarrido =>
      _modulos.fold<int>(0, (n, m) => n + m.camposDelUltimoBarrido);

  /// Los que el servidor dejó activos para este comercio.
  ///
  /// Si el servidor no dijo nada del módulo, **no corre**. Es a propósito: prender algo por
  /// omisión es pedirle a la persona un permiso que su comercio no pidió, y eso no se hace
  /// por un campo que faltó.
  Iterable<Modulo> activos(Contexto c) {
    final dicho = c.config?.modulos ?? const {};
    return _modulos.where((m) {
      final info = dicho[m.nombre];
      if (info == null) return false;
      return info.estado == 'activo';
    });
  }

  Future<void> alIniciar(Contexto c) => _atodos(c, 'alIniciar', (m) => m.alIniciar(c));
  Future<void> alEntrar(Contexto c) => _atodos(c, 'alEntrar', (m) => m.alEntrar(c));
  Future<void> alSalir(Contexto c) => _atodos(c, 'alSalir', (m) => m.alSalir(c));

  /// Cómo está cada uno. Para el diagnóstico.
  Future<Map<String, EstadoDeModulo>> estados(Contexto c) async {
    final salida = <String, EstadoDeModulo>{};
    for (final m in activos(c)) {
      try {
        salida[m.nombre] = await m.estado(c).timeout(_tope);
      } catch (e) {
        salida[m.nombre] = EstadoDeModulo(
          andando: false,
          ultimoMotivo: 'no se pudo consultar su estado: $e',
        );
      }
    }
    return salida;
  }

  /// 🔴 EN PARALELO, NO EN FILA.
  ///
  /// Los módulos no se conocen entre sí —lo dice el contrato—, así que no hay ninguna razón
  /// para que el segundo espere al primero. En fila, cuatro módulos con una llamada de red
  /// cada uno suman cuatro esperas en el arranque; en paralelo, una.
  Future<void> _atodos(
    Contexto c,
    String gancho,
    Future<void> Function(Modulo) hacer,
  ) async {
    await Future.wait(activos(c).map((m) async {
      try {
        await hacer(m).timeout(_tope);
      } catch (e) {
        // Se anota y se sigue. Que un módulo falle no puede arrastrar a los demás ni al
        // arranque — y en producción esto no imprime nada.
        assert(() {
          debugPrint('[collection] el módulo «${m.nombre}» falló en $gancho: $e');
          return true;
        }());
      }
    }));
  }
}
