/// UN EVENTO DE COMPORTAMIENTO — lo que la persona hizo DENTRO DE NUESTRA APLICACIÓN.
///
/// ══ POR QUÉ ESTO ES LO MÁS VALIOSO DEL COLECTOR, Y NO PIDE UN SOLO PERMISO ══
///
/// En 2019 Google cerró el acceso a los SMS y al registro de llamadas, que era de donde los
/// prestamistas sacaban su señal. Lo que quedó del otro lado de esa puerta —y no lo cerró
/// nadie, porque no hay nada que cerrar— es **lo que pasa adentro de la propia aplicación**:
/// a qué hora la abre, cuánto tarda en llenar una solicitud, cuántas veces la abandona y
/// vuelve, si pega la cédula o la escribe. Es nuestra pantalla, es nuestro formulario, y no
/// hay permiso que pedir porque no se está leyendo nada de nadie más.
///
/// ══ 🔴 EL LÍMITE DURO: EL CONTENIDO NO SE MIDE, Y NO ES NEGOCIABLE ══
///
/// Se mide **que pegó la cédula**, nunca **qué cédula pegó**. Se mide **cuánto tardó**,
/// nunca **qué escribió**. Un teclado que registra contenido es un programa espía, y no hay
/// justificación de negocio que lo salve.
///
/// Lo que eso significa acá, en concreto y para que nadie tenga que adivinarlo:
///
///   · Ningún evento lleva el texto de un campo. Ni entero, ni recortado, ni un carácter.
///   · Ningún evento lleva el LARGO de lo que se escribió. Se consideró y se descartó: no
///     hace falta para nada de lo que este módulo tiene que contestar, y es lo único de la
///     lista que se parece al contenido. Lo que se cuenta son las **correcciones**, que es
///     un número de acciones, no una medida del dato.
///   · Ningún evento lleva un hash del contenido. Un hash de una cédula es una cédula: hay
///     treinta millones de cédulas posibles y una tabla las recorre todas en un segundo.
///   · El NOMBRE del campo (`cedula`, `monto`) sí viaja, porque lo pone quien integra al
///     declarar el formulario. Es un rótulo del formulario, no algo que haya escrito la
///     persona.
///
/// ══ LOS NOMBRES DE LOS TIPOS NO SE INVENTAN ══
///
/// Están fijados en el contrato de la noche del 2026-09-04, y del otro lado hay un back
/// construyéndose contra esos mismos siete nombres al mismo tiempo. Cambiar uno acá sin
/// avisar es dejar eventos que el otro lado descarta sin decir nada.
library;

/// Los siete tipos del contrato. Ni uno más, y ninguno con otro nombre.
class TipoDeEvento {
  const TipoDeEvento._();

  /// La persona abrió la aplicación. `datos` lleva la hora local y el día de la semana,
  /// que es lo que `cuando` —que viaja en UTC— no puede reconstruir del otro lado.
  static const sesionAbre = 'SESION_ABRE';

  /// La aplicación se fue al fondo o se cerró. `ms` es cuánto duró la sesión.
  static const sesionCierra = 'SESION_CIERRA';

  /// Se abrió un formulario. `datos.vuelta` dice si es la primera vez que lo abre o la
  /// quinta — que es exactamente lo que mide «lo abandona y vuelve».
  static const formularioAbre = 'FORMULARIO_ABRE';

  /// Se envió. `ms` es cuánto tardó desde que lo abrió: el tiempo de llenado.
  static const formularioEnvia = 'FORMULARIO_ENVIA';

  /// Se fue sin enviarlo. `ms` es cuánto aguantó antes de irse.
  static const formularioAbandona = 'FORMULARIO_ABANDONA';

  /// El campo se llenó de un golpe: el dato ya estaba en algún lado y se trajo.
  static const campoPegado = 'CAMPO_PEGADO';

  /// El campo se llenó tecleando. `datos.correcciones` cuenta cuántas veces borró.
  static const campoEscrito = 'CAMPO_ESCRITO';

  /// Para poder validar sin repetir la lista a mano en tres lugares.
  static const todos = <String>[
    sesionAbre,
    sesionCierra,
    formularioAbre,
    formularioEnvia,
    formularioAbandona,
    campoPegado,
    campoEscrito,
  ];
}

/// Un evento, tal como se guarda en el teléfono y tal como viaja.
///
/// 🔴 [seq] y [sujetoId] NO son parte del evento del contrato: son de la cola. `seq` es un
/// número que sólo crece y sirve para dos cosas que no se pueden hacer sin él —borrar de la
/// cola exactamente lo que se mandó, y que el servicio pueda descartar un lote repetido si
/// la respuesta se perdió a mitad de camino—. `sujetoId` agrupa el lote: un evento pertenece
/// a quien estaba adentro cuando ocurrió, y una cola puede cruzar un cierre de sesión.
class EventoDeComportamiento {
  const EventoDeComportamiento({
    required this.tipo,
    required this.cuando,
    required this.seq,
    this.ms,
    this.datos = const {},
    this.sujetoId,
  });

  final String tipo;
  final DateTime cuando;
  final int seq;

  /// Cuánto duró lo que el evento mide. Nulo cuando el evento es un instante y no un lapso.
  final int? ms;

  /// Lo que hace falta para entender el evento. **Nunca contenido de un campo.**
  final Map<String, Object?> datos;

  /// Quién estaba adentro. Nulo es un valor legítimo y frecuente: la aplicación se abre
  /// antes de que nadie inicie sesión, y esos eventos son de la instalación. El servicio
  /// sabe a qué sujeto pertenece una instalación; acá no se adivina.
  final String? sujetoId;

  /// La forma del contrato, y sólo la del contrato: `tipo`, `cuando`, `ms`, `datos`.
  ///
  /// `seq` viaja adentro de `datos` —que es un mapa abierto— en vez de como un campo nuevo
  /// del evento: agregar un campo al lado de los cuatro sería cambiar el contrato por mi
  /// cuenta, y el mapa está justamente para esto.
  Map<String, Object?> aContrato() => {
        'tipo': tipo,
        'cuando': cuando.toUtc().toIso8601String(),
        if (ms != null) 'ms': ms,
        'datos': {...datos, 'seq': seq},
      };

  /// Cómo se guarda en el teléfono. Distinto del contrato a propósito: acá hace falta el
  /// sujeto y el `seq` suelto, que del otro lado no van en el mismo lugar.
  Map<String, Object?> aDisco() => {
        't': tipo,
        'c': cuando.toUtc().toIso8601String(),
        if (ms != null) 'm': ms,
        if (datos.isNotEmpty) 'd': datos,
        if (sujetoId != null) 's': sujetoId,
        'q': seq,
      };

  /// 🔴 Devuelve `null` en vez de reventar si la línea guardada no se entiende.
  ///
  /// Una versión vieja del paquete pudo dejar en el disco una forma que ésta no conoce. Que
  /// un evento ilegible tumbe la lectura de toda la cola sería perder cien eventos buenos
  /// por uno malo — y en el arranque de la aplicación, además.
  static EventoDeComportamiento? deDisco(Object? crudo) {
    if (crudo is! Map) return null;
    final tipo = crudo['t'];
    final cuando = DateTime.tryParse('${crudo['c']}');
    if (tipo is! String || cuando == null) return null;
    return EventoDeComportamiento(
      tipo: tipo,
      cuando: cuando,
      seq: (crudo['q'] as num?)?.toInt() ?? 0,
      ms: (crudo['m'] as num?)?.toInt(),
      datos: crudo['d'] is Map
          ? (crudo['d'] as Map).map((k, v) => MapEntry('$k', v))
          : const {},
      sujetoId: crudo['s'] as String?,
    );
  }

  @override
  String toString() => '$tipo@${cuando.toIso8601String()}'
      '${ms != null ? " ${ms}ms" : ""} $datos';
}
