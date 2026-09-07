/// EL RUBRO DEL COMERCIO, Y QUÉ CAMBIA SEGÚN CUÁL SEA.
///
/// 🔴 LA CORRECCIÓN QUE ORIGINA ESTE ARCHIVO, del 2026-08-31: el catálogo de permisos
/// nació con una lista plana de prohibidos, armada sobre la política de préstamos
/// personales de Google Play. Estaba mal, y de una forma que se veía tarde.
///
/// `READ_MEDIA_IMAGES` está vetado **para una aplicación de préstamo personal**. Para
/// una aseguradora que necesita la foto de un siniestro, o una operadora que verifica
/// identidad, no está vetado: está CONDICIONADO, que es otra cosa. Con una lista plana,
/// el día que un comercio de seguros pide fotos el muro le dice «prohibido» y no lo es —
/// y entonces alguien lo desactiva para poder trabajar.
///
/// **Un muro que miente en contra es tan inútil como uno que deja pasar**, porque los
/// dos terminan apagados.
///
/// Este SDK se licencia a rubros distintos —bancos, aseguradoras, operadoras,
/// comercios— y cualquiera de ellos puede necesitar cualquier permiso. Lo que cambia no
/// es si se puede: es **qué hay que hacer para que te lo aprueben**.
library;

/// A qué se dedica el comercio que instala el SDK.
///
/// No es una taxonomía de negocio: es la lista de rubros que las tiendas tratan
/// distinto. Si Google y Apple no le ponen reglas propias a un rubro, no tiene por qué
/// estar acá — y agregar uno que no cambia nada sólo hace más difícil elegir el correcto.
enum Rubro {
  /// 🔴 EL MÁS RESTRINGIDO DE TODOS. Préstamo no recurrente entre partes: préstamo
  /// rápido, adelanto de sueldo, empeño. Google le prohíbe expresamente fotos y
  /// contactos. Si hay duda entre éste y `banca`, se elige éste: equivocarse para el
  /// lado restrictivo cuesta un permiso; para el otro, la aplicación.
  prestamoPersonal,

  /// Banco, casa de bolsa, tarjeta, hipoteca, crédito de auto, crédito rotativo. La
  /// política de préstamos personales los EXCLUYE expresamente de su definición.
  banca,

  /// Seguros. Necesita fotos de siniestros y a veces datos de salud, que es una
  /// categoría sensible con reglas propias.
  seguros,

  /// Operadora telefónica. Trabaja con datos de red y de línea que en otros rubros
  /// serían caros de justificar.
  telco,

  /// Comercio, tienda, mercado. Financiamiento de compra incluido.
  comercio,

  /// Transporte, reparto, logística. Es el rubro donde la ubicación en segundo plano
  /// tiene una justificación que Google acepta con más facilidad.
  transporte,

  /// Salud. Categoría con reglas propias y con dato sensible por definición.
  salud,

  /// Cuando todavía no se sabe. **El muro trata esto como el caso más restrictivo**, a
  /// propósito: un comercio sin rubro declarado no puede pedir nada caro hasta que
  /// alguien conteste a qué se dedica.
  sinDeclarar,
}

/// En qué situación está un permiso para un rubro dado.
enum Estado {
  /// Se pide y ya. No hay formulario ni revisión.
  libre,

  /// Se puede pedir, **pero hay que cumplir requisitos concretos** antes: un formulario,
  /// una pantalla de aviso, un video, una política publicada. Los requisitos están en la
  /// ficha del permiso, y son lo que hay que hacer, no una advertencia genérica.
  condicionado,

  /// Para ESE rubro no se puede, y la ficha dice qué política lo prohíbe.
  prohibido,
}

/// Qué hay que hacer para que te aprueben un permiso condicionado.
///
/// 🔴 NO ES UNA ADVERTENCIA, ES UNA LISTA DE TAREAS. La diferencia importa: «este
/// permiso es delicado» no le sirve a nadie; «hay que llenar el formulario X, mostrar
/// una pantalla que diga Y antes del diálogo, y mandar un video que muestre Z» sí.
class Requisito {
  /// Qué hay que hacer, en imperativo y concreto.
  final String queHacer;

  /// De dónde sale la exigencia. Se guarda la URL para poder volver a comprobarla: las
  /// políticas de las tiendas cambian, y un requisito citado de memoria es peligroso.
  final String fuente;

  const Requisito(this.queHacer, {required this.fuente});
}

/// Para qué rubros se puede pedir un permiso, y para cuáles no.
///
/// Se declara con un valor por omisión y las excepciones, en vez de enumerar los ocho
/// rubros en cada permiso: así una ficha dice de un vistazo cuál es la regla general y
/// quién se sale de ella, que es como de verdad funcionan las políticas.
class Disponibilidad {
  /// Lo que vale para los rubros que no aparecen en `excepciones`.
  final Estado porOmision;

  /// Los rubros que se salen de la regla general.
  final Map<Rubro, Estado> excepciones;

  /// Por qué es así, en una frase. Es el texto que muestra el muro cuando bloquea, y
  /// tiene que decirle a quien lo lee qué política lo decide.
  final String porQue;

  const Disponibilidad({
    required this.porOmision,
    required this.porQue,
    this.excepciones = const {},
  });

  /// En qué estado queda este permiso para un rubro concreto.
  ///
  /// 🔴 `sinDeclarar` se resuelve al caso más restrictivo que exista para este permiso,
  /// y no al valor por omisión. Un comercio que no dijo a qué se dedica no puede pedir
  /// algo caro por el hecho de no haber contestado — sería premiar el silencio.
  Estado para(Rubro rubro) {
    if (rubro == Rubro.sinDeclarar) {
      if (porOmision == Estado.prohibido ||
          excepciones.containsValue(Estado.prohibido)) {
        return Estado.prohibido;
      }
      if (porOmision == Estado.condicionado ||
          excepciones.containsValue(Estado.condicionado)) {
        return Estado.condicionado;
      }
      return Estado.libre;
    }
    return excepciones[rubro] ?? porOmision;
  }

  /// Atajos para las tres formas que más se repiten, para que las fichas se lean.

  /// Libre para todos. Se usa en los permisos de nivel 0 que no le muestran nada a nadie.
  static Disponibilidad libreParaTodos(String porQue) =>
      Disponibilidad(porOmision: Estado.libre, porQue: porQue);

  /// Condicionado en general, con la lista de rubros donde está directamente prohibido.
  static Disponibilidad condicionadoSalvo(
    List<Rubro> prohibidoEn, {
    required String porQue,
  }) =>
      Disponibilidad(
        porOmision: Estado.condicionado,
        porQue: porQue,
        excepciones: {for (final r in prohibidoEn) r: Estado.prohibido},
      );
}

/// ─────────────────────────────────────────────────────────────────────────────────
/// LA PUERTA, CERRADA CON LLAVE PERO CON BISAGRAS
/// ─────────────────────────────────────────────────────────────────────────────────

/// Qué cuenta como dato sensible. No es una opinión: es lo que las leyes de la región
/// listan como categoría especial, y tocar una dispara obligaciones extra
/// —consentimiento explícito, cifrado, a veces evaluación de impacto—.
///
/// Brasil y Colombia listan la **biometría** expresamente, y ahí entra la biometría de
/// comportamiento: medir cómo alguien escribe o toca para identificarlo es dato
/// sensible en esos dos países, aunque suene técnico e inofensivo.
enum DatoSensible {
  salud,
  biometria,
  origenRacialOEtnico,
  religion,
  opinionPolitica,
  afiliacionSindical,
  vidaSexualUOrientacion,
  datosDeMenores,
}

/// 🔴 LA POSICIÓN DEL SISTEMA HOY: NO SE TRABAJA CON DATO SENSIBLE. Prohibido, y no
/// depende del rubro del comercio ni de lo que las tiendas permitan.
///
/// Decisión de Juan, 2026-08-31. La arquitectura queda preparada —el modelo de rubros,
/// estados y requisitos de arriba está entero y sirve tal cual— pero **la puerta está
/// cerrada**: aunque el rubro de un comercio permita pedir algo sensible, este
/// interruptor gana y devuelve prohibido.
///
/// Por qué forzado y no anotado: una nota en un comentario se pasa por alto seis meses
/// después, cuando el que la escribió ya no está mirando. Una regla que devuelve
/// «prohibido» no se pasa por alto — hay que ir a cambiarla a propósito, y ese acto
/// deliberado es exactamente la fricción que queremos que exista.
///
/// **Para abrirla el día que se decida:** poner esto en `true` NO alcanza y es a
/// propósito. Antes hacen falta las tres cosas que un dato sensible obliga y que hoy no
/// existen: consentimiento explícito por categoría, borrado a pedido, y registro de
/// quién accedió. Están anotadas como fases 7 y 8 del plan.
const bool sistemaAdmiteDatoSensible = false;

/// ¿Este permiso toca alguna categoría sensible?
///
/// Se declara en la ficha del permiso y lo consulta el muro. Un permiso que toca dato
/// sensible queda prohibido mientras `sistemaAdmiteDatoSensible` sea `false`, sin
/// importar el rubro.
Estado conLaPuertaCerrada(Estado estado, List<DatoSensible> toca) {
  if (toca.isEmpty) return estado;
  if (sistemaAdmiteDatoSensible) return estado;
  return Estado.prohibido;
}

/// El motivo que muestra el muro cuando bloquea por esto. Se dice que es decisión
/// nuestra y no de la tienda, porque son dos cosas distintas y confundirlas hace que
/// alguien vaya a discutir con Google algo que decidimos nosotros.
const String motivoPuertaCerrada =
    'Este sistema no trabaja con datos sensibles. Es una decisión propia del '
    '2026-08-31, no una restricción de la tienda: la arquitectura está preparada, pero '
    'la puerta está cerrada hasta que existan consentimiento explícito por categoría, '
    'borrado a pedido y registro de accesos.';
