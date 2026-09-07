import 'package:flutter/material.dart';

import 'permiso.dart';

/// EL ESTADO DE LOS AVISOS, EN CASTELLANO Y LISTO PARA DIBUJAR
///
/// El SDK ya sabía si había permiso o no ([EstadoDelPermiso]), pero eso son cinco
/// valores de un `enum` que cada aplicación tenía que traducir por su cuenta a algo
/// que una persona entienda — y a la tercera aplicación hay tres traducciones
/// distintas, dos de ellas mal.
///
/// 🔴 Sobre todo la que importa: la diferencia entre «te lo puedo preguntar» y «ya no
/// te lo puedo preguntar, andá a los Ajustes». Si se confunden, la aplicación le
/// ofrece a alguien un botón de «Activar avisos» que **no puede hacer nada** —el
/// sistema ya no muestra el diálogo—, la persona lo toca, no pasa nada, y a la
/// segunda vez deja de creerle a la aplicación.
class EstadoDeAvisos {
  const EstadoDeAvisos._({
    required this.permiso,
    required this.titulo,
    required this.explicacion,
    required this.accion,
    required this.puedeRecibir,
    required this.hayQueIrAAjustes,
  });

  /// El estado crudo, para quien quiera decidir por su cuenta.
  final EstadoDelPermiso permiso;

  /// Una línea para el encabezado. «Avisos activados», «Avisos apagados».
  final String titulo;

  /// Qué significa, en la voz de quien lo lee. Sirve tal cual para un cuerpo de texto.
  final String explicacion;

  /// Qué dice el botón — o `null` cuando no hay nada que hacer porque ya está todo bien.
  ///
  /// El texto cambia según lo que el botón vaya a hacer de verdad: «Activar los avisos»
  /// cuando todavía se puede preguntar, «Abrir los ajustes» cuando ya no. Un botón que
  /// promete una cosa y hace otra es peor que no tenerlo.
  final String? accion;

  /// Si los avisos llegan hoy.
  final bool puedeRecibir;

  /// Si la única salida son los Ajustes del teléfono porque el sistema ya no pregunta.
  final bool hayQueIrAAjustes;

  /// Si hay algo que ofrecerle a la persona. Es la condición para pintar el punto rojo.
  bool get hayAlgoQueHacer => accion != null;

  /// 🔴 EL TEXTO SE TUTEA. NUNCA SE VOSEA.
  ///
  /// Estas cuatro frases estaban voseadas —«si lo activás», «podés», «para
  /// vos»— y salieron a pantalla en la app de Rodar el 2026-09-07. El producto
  /// habla **castellano de Venezuela**, donde se tutea, y el voseo suena
  /// extranjero: la campanita es una de las pocas veces que la aplicación PIDE
  /// algo, y pedir con acento de otro país es el peor momento para no sonar de
  /// acá.
  ///
  /// Es el defecto que más se cuela porque el imperativo es donde más se nota:
  /// «activá» / «activa» difieren en una letra.
  factory EstadoDeAvisos.de(EstadoDelPermiso p) {
    switch (p) {
      case EstadoDelPermiso.concedido:
        return const EstadoDeAvisos._(
          permiso: EstadoDelPermiso.concedido,
          titulo: 'Avisos activados',
          explicacion: 'Te vamos a avisar acá cuando haya algo importante para ti.',
          accion: null,
          puedeRecibir: true,
          hayQueIrAAjustes: false,
        );

      case EstadoDelPermiso.sinPreguntar:
        return const EstadoDeAvisos._(
          permiso: EstadoDelPermiso.sinPreguntar,
          titulo: 'Avisos apagados',
          explicacion:
              'Todavía no nos diste permiso para avisarte. Si los activas, te escribimos '
              'sólo cuando haya algo que te sirva saber.',
          accion: 'Activar los avisos',
          puedeRecibir: false,
          hayQueIrAAjustes: false,
        );

      case EstadoDelPermiso.denegado:
        // 🔴 Todavía se puede preguntar, pero es la ÚLTIMA vez: en Android 13+ alcanzan
        // dos descartes para que el sistema no vuelva a mostrar nada. Por eso el texto
        // explica para qué sirve antes de gastar ese último diálogo.
        return const EstadoDeAvisos._(
          permiso: EstadoDelPermiso.denegado,
          titulo: 'Avisos apagados',
          explicacion:
              'Los avisos están apagados, así que no te vamos a poder escribir. Puedes '
              'activarlos ahora si quieres enterarte de lo tuyo.',
          accion: 'Activar los avisos',
          puedeRecibir: false,
          hayQueIrAAjustes: false,
        );

      case EstadoDelPermiso.denegadoParaSiempre:
        // La única honesta: el botón NO promete activar nada, porque no puede.
        return const EstadoDeAvisos._(
          permiso: EstadoDelPermiso.denegadoParaSiempre,
          titulo: 'Avisos bloqueados',
          explicacion:
              'Este teléfono tiene los avisos bloqueados para la aplicación y ya no nos '
              'deja preguntártelo de nuevo. Se activan desde los ajustes del teléfono.',
          accion: 'Abrir los ajustes',
          puedeRecibir: false,
          hayQueIrAAjustes: true,
        );

      case EstadoDelPermiso.provisional:
        return const EstadoDeAvisos._(
          permiso: EstadoDelPermiso.provisional,
          titulo: 'Avisos en silencio',
          explicacion:
              'Los avisos te llegan al centro de notificaciones, pero sin sonido ni '
              'cartel. Puedes darles aviso completo desde los ajustes.',
          accion: 'Abrir los ajustes',
          puedeRecibir: true,
          hayQueIrAAjustes: true,
        );
    }
  }
}

/// LA CAMPANITA, HECHA
///
/// Un ícono de campana con un punto cuando hay algo que resolver. Al tocarla abre una
/// hoja que dice cómo están los avisos y —si están apagados— ofrece el único botón que
/// de verdad puede arreglarlo en ese estado.
///
/// Se usa así, y no hace falta nada más:
///
/// ```dart
/// AppBar(actions: const [CampanitaDeAvisos()])
/// ```
///
/// 🔴 Se actualiza sola cuando la aplicación vuelve del fondo. Es lo que hace que
/// funcione el caso que importa: la persona va a los Ajustes del teléfono, activa los
/// avisos, vuelve — y la campana ya está en verde. Sin eso queda mostrando «apagados»
/// hasta que alguien reinicie la aplicación, y la persona cree que no le sirvió de nada
/// haber ido.
///
/// Quien prefiera dibujar lo suyo tiene los mismos servicios sueltos:
/// `AkPush.avisos` (un `ValueListenable` que se actualiza igual),
/// `AkPush.estadoDeAvisos()` y `AkPush.resolverAvisos()`.
class CampanitaDeAvisos extends StatefulWidget {
  const CampanitaDeAvisos({
    super.key,
    this.color,
    this.alResolver,
    this.estado,
    this.resolver,
  });

  final Color? color;

  /// Se llama cuando la persona terminó de decidir, con el estado que quedó.
  final void Function(EstadoDeAvisos)? alResolver;

  /// Cómo se lee el estado. Lo inyecta `AkPush`; sólo se pasa a mano en pruebas.
  final Future<EstadoDeAvisos> Function()? estado;

  /// Qué hace el botón. Lo inyecta `AkPush`.
  final Future<EstadoDeAvisos> Function()? resolver;

  @override
  State<CampanitaDeAvisos> createState() => _CampanitaDeAvisosState();
}

class _CampanitaDeAvisosState extends State<CampanitaDeAvisos>
    with WidgetsBindingObserver {
  EstadoDeAvisos? _estado;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refrescar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // El momento exacto que hace útil a este widget: se vuelve de los Ajustes.
    if (estado == AppLifecycleState.resumed) _refrescar();
  }

  Future<void> _refrescar() async {
    final f = widget.estado;
    if (f == null) return;
    final e = await f();
    if (mounted) setState(() => _estado = e);
  }

  @override
  Widget build(BuildContext context) {
    final e = _estado;
    final color = widget.color ?? Theme.of(context).colorScheme.onSurface;
    final avisar = e != null && e.hayAlgoQueHacer;

    return IconButton(
      // Lo que lee un lector de pantalla. Sin esto la campana es «botón» a secas.
      tooltip: e?.titulo ?? 'Avisos',
      onPressed: e == null ? null : () => _abrir(e),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            e?.puedeRecibir == true
                ? Icons.notifications_outlined
                : Icons.notifications_off_outlined,
            color: color,
          ),
          if (avisar)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  shape: BoxShape.circle,
                  // El borde del color de la barra: sin él, el punto se confunde con
                  // el trazo del ícono y parece suciedad en la pantalla.
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _abrir(EstadoDeAvisos e) async {
    final tema = Theme.of(context);
    final quiere = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: tema.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: tema.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: (e.puedeRecibir
                          ? tema.colorScheme.primary
                          : tema.colorScheme.error)
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  e.puedeRecibir
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  size: 28,
                  color: e.puedeRecibir
                      ? tema.colorScheme.primary
                      : tema.colorScheme.error,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                e.titulo,
                style: tema.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                e.explicacion,
                style: tema.textTheme.bodyMedium?.copyWith(
                  color: tema.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              if (e.accion != null)
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(e.accion!),
                ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: tema.colorScheme.onSurfaceVariant,
                ),
                child: Text(e.accion == null ? 'Cerrar' : 'Ahora no'),
              ),
            ],
          ),
        ),
      ),
    );

    if (quiere != true) return;
    final f = widget.resolver;
    if (f == null) return;
    final nuevo = await f();
    if (mounted) setState(() => _estado = nuevo);
    widget.alResolver?.call(nuevo);
  }
}
