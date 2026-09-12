import 'dart:async';

import 'package:flutter/widgets.dart';

import '../modal_de_ubicacion.dart';
import '../politica.dart';
import '../ubicacion.dart';
import 'modulo.dart';

/// LA ZONA DONDE ESTÁ LA PERSONA, CUANDO ELLA LO PERMITE.
///
/// Sirve para dos cosas concretas: segmentar un envío por zona sin que el comercio tenga que
/// mandar la ciudad de cada quien, y ver por dónde anduvo un aparato.
///
/// ══ POR QUÉ ESTE ARCHIVO EXISTE ══
///
/// Todo esto vivía repartido en la fachada: siete métodos estáticos, un campo, una política,
/// tres líneas en el diagnóstico y dos en el inicio de sesión. Cada módulo nuevo iba a
/// agregar otros siete. Acá está junto, y la fachada no lo nombra.
///
/// ══ SÓLO APROXIMADA, Y ES UNA DECISIÓN ══
///
/// Se pide `locationWhenInUse`, que en Android es la aproximada. La precisa la acepta ~25%
/// de la gente contra ~40% la aproximada, y la de segundo plano ~10% **más un video
/// justificando el uso ante Google**. Para saber en qué zona está alguien, la aproximada
/// alcanza y sobra.
class ModuloDeUbicacion extends Modulo {
  ModuloDeUbicacion(this._ubicacion, this._politica, this._navegador);

  final Ubicacion _ubicacion;
  final PoliticaDeUbicacion Function() _politica;

  /// De dónde sacar una pantalla para dibujar el modal. Puede devolver `null` si la
  /// aplicación no le prestó su `navigatorKey` — y entonces el módulo no pregunta nada.
  ///
  /// 🔴 ESTÁ TIPADO, Y ANTES ERA `dynamic Function()`. Con `dynamic` el compilador no miraba
  /// nada: la fachada le pasaba el `GlobalKey` del navegador entero en vez de su contexto y
  /// el módulo reventaba recién al entrar, en tiempo de ejecución: «type
  /// `LabeledGlobalKey<NavigatorState>` is not a subtype of type `BuildContext`». Medido en el
  /// emulador el 2026-09-11. El tipo es lo que convierte ese error en un error de compilación.
  final BuildContext? Function() _navegador;

  @override
  String get nombre => 'ubicacion';

  /// 🔴 LA CADENCIA DEPENDE DEL MODO QUE ELIGIÓ EL COMERCIO, no del módulo.
  ///
  /// El mismo módulo mide una vez por sesión o mide todo el día según lo que diga la
  /// consola. Declarar `periodica` fijo haría que el catálogo le mostrara a un comercio con
  /// segundo plano prendido una cadencia que no es la suya — y la cadencia es la mitad de lo
  /// que decide cuánto cuesta en batería y en tráfico.
  @override
  Cadencia get cadencia => switch (_politica().modo) {
        ModoDeLectura.alEntrar => Cadencia.periodica,
        ModoDeLectura.enPrimerPlano => Cadencia.periodica,
        ModoDeLectura.enSegundoPlano => Cadencia.continua,
      };

  /// 🔴 Y LOS PERMISOS TAMBIÉN. Se declaran **para poder decirlos**, no para pedirlos: es lo
  /// que le permite a la consola mostrar en gris lo que el APK no trae, y armarle al comercio
  /// la lista exacta de renglones que tiene que agregar a SU manifiesto antes de que el modo
  /// de segundo plano pueda andar. Ver `Ubicacion.sePuedeEnSegundoPlano`.
  @override
  List<String> get permisos => switch (_politica().modo) {
        ModoDeLectura.enSegundoPlano => const [
            'android.permission.ACCESS_COARSE_LOCATION',
            'android.permission.ACCESS_BACKGROUND_LOCATION',
            'android.permission.FOREGROUND_SERVICE',
            'android.permission.FOREGROUND_SERVICE_LOCATION',
          ],
        _ => const ['android.permission.ACCESS_COARSE_LOCATION'],
      };

  /// El nivel también: el segundo plano es el único trámite de este SDK que Google revisa a
  /// mano, con formulario y video. Decir «permiso simple» de eso sería mentirle al comercio
  /// sobre lo que le va a costar publicar.
  @override
  int get nivel => _politica().modo == ModoDeLectura.enSegundoPlano
      ? Nivel.revisionDeGoogle
      : Nivel.permisoSimple;

  /// 🔴 NO SE PIDE EN EL ARRANQUE. NUNCA.
  ///
  /// Dos diálogos del sistema seguidos apenas se abre la aplicación es la forma más rápida
  /// de que la persona diga que no a los dos — y el de notificaciones es el que el producto
  /// necesita. Acá sólo se manda lo que ya se tenga permitido.
  @override
  Future<void> alIniciar(Contexto c) async {
    if (!await _ubicacion.concedido) return;
    if (c.sujetoId != null) await _ubicacion.reportarSiCorresponde(c.sujetoId!);
  }

  /// Al entrar es donde se ofrece, **después** de que el permiso de avisos se resolvió.
  @override
  Future<void> alEntrar(Contexto c) async {
    final id = c.sujetoId;
    if (id == null) return;

    // A quien ya dio permiso se le lee y listo. El freno de seis horas vive adentro de
    // `reportarSiCorresponde`, así que llamarlo en cada inicio no gasta batería.
    if (await _ubicacion.concedido) {
      await _ubicacion.reportarSiCorresponde(id);
      return;
    }

    // Y a quien no, se le ofrece — si el comercio lo activó y si el sistema todavía admite
    // preguntar. Un modal que pide algo que el sistema ya no va a mostrar no lleva a ningún
    // lado salvo a confundir.
    final p = _politica();
    if (!p.activa || p.momento != MomentoDeUbicacion.despuesDeEntrar) return;
    if (!await _ubicacion.sePuedePreguntar) return;

    // Se busca DESPUÉS del último `await`, y se exige que siga montado: entre consultar el
    // permiso y dibujar, la aplicación pudo cambiar de pantalla, y un contexto muerto no
    // dibuja el modal ni avisa por qué.
    final ctx = _navegador();
    if (ctx == null || !ctx.mounted) return;
    final quiere = await ModalDeUbicacion.mostrar(ctx, textos: p.textos);
    if (!quiere) return;
    if (await _ubicacion.pedir()) {
      await _ubicacion.reportarSiCorresponde(id, forzar: true);
    }
  }

  @override
  Future<EstadoDeModulo> estado(Contexto c) async {
    final permitida = await _ubicacion.concedido;
    final prendida = await _ubicacion.servicioPrendido;
    final falta = <String>[
      if (!permitida) 'sin permiso',
      if (!prendida) 'el teléfono tiene la ubicación apagada',
    ];
    return EstadoDeModulo(
      // 🔴 Los dos interruptores puestos y cero posiciones NO es «anda». Un eslabón en
      // verde que hay que leer con lupa para descubrir que está en rojo es peor que no
      // tenerlo: el que diagnostica lo saltea.
      andando: permitida && prendida &&
          (_ubicacion.ultimoEnvio != null || _ubicacion.ultimoMotivo == null),
      detalle: falta.isNotEmpty
          ? falta.join(' + ')
          : (_ubicacion.ultimoEnvio == null
              ? 'nunca se mandó una posición'
              : 'última hace ${DateTime.now().difference(_ubicacion.ultimoEnvio!).inMinutes} min'),
      ultimoMotivo: _ubicacion.ultimoMotivo,
      ultimaVez: _ubicacion.ultimoEnvio,
    );
  }
}
