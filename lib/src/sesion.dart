import 'permiso.dart';
import 'politica.dart';

/// Qué quedó después de iniciar sesión.
///
/// ## Por qué devuelve tanto
///
/// Registrar el teléfono no es lo mismo que dejarlo en condiciones de recibir, y
/// hasta ahora el SDK sólo hacía lo primero y volvía en silencio. Una persona
/// podía quedar registrada y muda —porque denegó el permiso— sin que la
/// aplicación tuviera forma de enterarse.
///
/// Esto es lo que la aplicación necesita para decidir qué mostrarle: si le va a
/// llegar, por qué no, y qué puede hacer al respecto.
class ResultadoDeSesion {
  const ResultadoDeSesion({
    required this.puedeRecibir,
    required this.estadoDelPermiso,
    required this.accionSugerida,
    required this.huboCambioDePersona,
    required this.seRegistro,
    required this.motivo,
  });

  /// El resumen que casi siempre alcanza: ¿le va a llegar un aviso a esta
  /// persona en este teléfono, ahora?
  final bool puedeRecibir;

  final EstadoDelPermiso estadoDelPermiso;

  /// Lo que la política del comercio dice que hay que hacer **ahora**. Si es
  /// [AccionDePermiso.mostrarPreguntaBlanda], le toca a la aplicación: el SDK no
  /// dibuja pantallas ajenas.
  final AccionDePermiso accionSugerida;

  /// Había otra persona con sesión abierta en este teléfono y se la dio de baja.
  ///
  /// Importa más de lo que parece: sin esto, un teléfono que cambia de manos deja
  /// a la persona anterior recibiendo los avisos de su cuenta.
  final bool huboCambioDePersona;

  /// Si hizo falta tocar el servidor. `false` significa que ya estaba todo como
  /// tenía que estar.
  final bool seRegistro;

  /// Una frase que explica el resultado, para poner en un registro o en un
  /// ticket. Nunca para mostrarle a la persona: la aplicación escribe lo que le
  /// muestra a su gente, con su voz.
  final String motivo;

  @override
  String toString() => 'ResultadoDeSesion(puedeRecibir: $puedeRecibir, '
      'permiso: ${estadoDelPermiso.name}, accion: ${accionSugerida.name}, '
      'cambioDePersona: $huboCambioDePersona, seRegistro: $seRegistro)';
}

/// Lo que hay que recordar entre un inicio de sesión y el siguiente, para no
/// registrar de más.
class HuellaDelRegistro {
  const HuellaDelRegistro({
    required this.userId,
    required this.token,
    required this.permisoConcedido,
    required this.cuando,
    this.huellaDeDatos,
  });

  final String userId;
  final String token;
  final bool permisoConcedido;

  /// Resumen de los datos que el comercio manda de esta persona.
  ///
  /// 🔴 SIN ESTO, UN CAMBIO DE DATOS NO LLEGA NUNCA. La sucursal de una persona
  /// cambia, y el plan más todavía: si la huella no los mira, el SDK ve «mismo
  /// usuario, mismo token, mismo permiso», da el registro por hecho y no vuelve
  /// a llamar. El servidor se queda con la sucursal vieja para siempre y los
  /// envíos segmentados le pegan al grupo equivocado, sin ningún error.
  ///
  /// Se guarda el resumen y no los datos: la huella se compara, no se lee, y
  /// dejar copiados el nombre y el correo de la persona en el almacenamiento
  /// del teléfono es guardar datos personales que no hacen falta.
  ///
  /// 🔴 Esta huella es del alta del TOKEN (`/api/v1/dispositivos`), no del
  /// alta del SUJETO (`/api/v1/sujetos`). El `tipo`, el `documento` y la
  /// `organizacion` que se agregaron con el rediseño de colecciones NO viajan
  /// por acá ni tienen que entrar en este resumen: esa alta no se acota con
  /// ninguna huella, se llama en CADA inicio de sesión — ver el comentario en
  /// `AkPush._alIniciarSesion`. Si algún día ese dato empezara a viajar
  /// TAMBIÉN por el alta del token, ahí sí tendría que entrar acá, o —tal
  /// como advierte esta nota— un cambio no llegaría nunca al servidor sin que
  /// ningún error lo delate.
  final String? huellaDeDatos;

  /// El resumen que se compara. Las claves van ordenadas para que el mismo mapa
  /// escrito en otro orden no parezca un cambio.
  static String? resumirDatos(Map<String, dynamic>? datos) {
    if (datos == null || datos.isEmpty) return null;
    final claves = datos.keys.toList()..sort();
    return claves.map((k) => '\$k=\${datos[k]}').join('&').hashCode.toString();
  }

  /// Cuándo se registró. Es lo que le pone techo a lo que la huella puede
  /// equivocarse — ver [venció].
  final DateTime cuando;

  /// Registrar de nuevo lo mismo es una llamada de red que no cambia nada. Y no
  /// alcanza con comparar el token: si la persona concedió el permiso desde los
  /// Ajustes del teléfono, el token es el mismo y **el servidor tiene que
  /// enterarse igual**, porque filtra por eso antes de enviar.
  bool esLoMismoQue(
    String otroUserId,
    String otroToken,
    bool otroPermiso, [
    String? otraHuellaDeDatos,
  ]) =>
      userId == otroUserId &&
      token == otroToken &&
      permisoConcedido == otroPermiso &&
      huellaDeDatos == otraHuellaDeDatos;

  /// 🔴 La huella es LOCAL, y puede mentir.
  ///
  /// Si el mantenimiento del servidor limpia este dispositivo, o el comercio lo
  /// borra desde su consola, el teléfono no se entera de nada: sigue creyendo
  /// que está registrado y no vuelve a registrarse **nunca**. Queda mudo para
  /// siempre, sin un solo error.
  ///
  /// No hay forma de detectarlo desde el teléfono, así que no se detecta: se
  /// **acota**. Pasado este plazo la huella se considera vencida y se registra
  /// igual, aunque nada haya cambiado. Cuesta una llamada cada tantos días y le
  /// pone un techo a cuánto tiempo puede estar equivocada.
  ///
  /// De dónde salió el plazo: la app Ionic de la que venimos revalidaba cada 24
  /// horas, pero con un temporizador dentro de la aplicación corriendo — que en
  /// un teléfono casi nunca llega a dispararse, porque el sistema mata la app
  /// mucho antes. Acá se mira **el tiempo transcurrido en cada inicio de
  /// sesión**, así que funciona igual aunque la cierren todas las noches.
  bool vencio(DateTime ahora, int maxDias) =>
      ahora.difference(cuando).inDays >= maxDias;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'token': token,
        'permisoConcedido': permisoConcedido,
        'cuando': cuando.toIso8601String(),
        if (huellaDeDatos != null) 'huellaDeDatos': huellaDeDatos,
      };

  static HuellaDelRegistro? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final cuando = DateTime.tryParse(j['cuando'] as String? ?? '');
    // Una huella sin fecha es de una versión anterior del paquete. Se la trata
    // como vencida —fecha cero— para que se registre de nuevo una vez y quede
    // sana. Descartarla entera perdería el resto del dato sin necesidad.
    return HuellaDelRegistro(
      userId: j['userId'] as String,
      token: j['token'] as String,
      permisoConcedido: j['permisoConcedido'] as bool? ?? true,
      cuando: cuando ?? DateTime.fromMillisecondsSinceEpoch(0),
      huellaDeDatos: j['huellaDeDatos'] as String?,
    );
  }
}

/// Decide qué hacer al iniciar sesión, sin tocar la plataforma ni la red.
///
/// Toda la lógica del ciclo de sesión vive acá, separada de quien la ejecuta, y
/// por eso se puede probar entera en la máquina. Lo que queda afuera —pedirle el
/// permiso al sistema, hablar con el servidor— es mecánico.
class PlanDeSesion {
  const PlanDeSesion({
    required this.darDeBajaALaAnterior,
    required this.pedirPermiso,
    required this.registrar,
    required this.accionSugerida,
  });

  /// Hay que dar de baja a la persona que estaba antes en este teléfono.
  final bool darDeBajaALaAnterior;

  /// Hay que disparar el diálogo del sistema antes de registrar.
  final bool pedirPermiso;

  /// Hay que registrar en el servidor.
  final bool registrar;

  final AccionDePermiso accionSugerida;
}

/// Arma el plan del inicio de sesión.
///
/// Los pasos, y por qué van en este orden:
///
/// 1. **Si entra otra persona, primero se da de baja a la anterior.** Antes de
///    tocar nada más: si el registro nuevo falla a mitad, el teléfono tiene que
///    quedar sin dueño y no con el anterior, que seguiría recibiendo lo suyo.
/// 2. **Se decide sobre el permiso según la política.** Es el momento en que la
///    persona ya sabe qué es la aplicación, y por eso es donde más conviene
///    preguntar.
/// 3. **Se registra**, con el permiso ya resuelto — para que el servidor guarde
///    el estado de verdad y no el de hace un segundo.
PlanDeSesion planearInicioDeSesion({
  required PoliticaDeNotificaciones politica,
  required String userId,
  required EstadoDelPermiso estado,
  required String? token,
  required String? userIdAnterior,
  required HuellaDelRegistro? ultimoRegistro,
  required bool yaSePregunto,
  required DateTime ahora,
  /// Resumen de los datos que manda el comercio. Si cambió, hay que registrar
  /// de nuevo aunque todo lo demás sea idéntico — ver `HuellaDelRegistro`.
  String? huellaDeDatos,
  int maxDiasSinRevalidar = 7,
  Duration? desdeLaUltimaPregunta,
}) {
  final cambioDePersona = userIdAnterior != null && userIdAnterior != userId;

  final accion = decidirQueHacer(
    politica: politica,
    disparador: Disparador.login,
    estado: estado,
    yaSePregunto: yaSePregunto,
    desdeLaUltimaPregunta: desdeLaUltimaPregunta,
  );

  final concedido = estado == EstadoDelPermiso.concedido ||
      estado == EstadoDelPermiso.provisional;

  // Sin token no hay nada que registrar. No es un fallo: es lo que pasa cuando
  // la persona todavía no dio permiso.
  //
  // 🔴 Pero si cambió de persona, igual hay que registrar aunque el estado sea
  // idéntico: la huella anterior era de OTRA persona, y compararse contra ella
  // dejaría a esta sin registrar.
  final registrar = token != null &&
      (cambioDePersona ||
          ultimoRegistro == null ||
          !ultimoRegistro.esLoMismoQue(userId, token, concedido, huellaDeDatos) ||
          // Aunque no haya cambiado nada: la huella es local y el servidor pudo
          // haber limpiado este dispositivo sin que el teléfono se entere.
          ultimoRegistro.vencio(ahora, maxDiasSinRevalidar));

  return PlanDeSesion(
    darDeBajaALaAnterior: cambioDePersona,
    pedirPermiso: accion == AccionDePermiso.pedirAlSistema,
    registrar: registrar,
    accionSugerida: accion,
  );
}

/// La frase que explica por qué esta persona puede o no recibir.
///
/// Se elige por el PRIMER motivo que lo impide, en orden de gravedad: de nada
/// sirve decir «no está registrada» si además denegó el permiso, porque
/// arreglar lo primero no cambiaría nada.
String motivoDeSesion({
  required EstadoDelPermiso estado,
  required bool hayToken,
  required bool registrado,
}) {
  if (estado.soloQuedanLosAjustes) {
    return 'La persona denegó las notificaciones y no se puede volver a '
        'preguntar desde la aplicación. Lo único que queda es ofrecerle los '
        'Ajustes del teléfono.';
  }
  if (estado == EstadoDelPermiso.denegado) {
    return 'La persona denegó las notificaciones. Todavía se le puede volver a '
        'preguntar.';
  }
  if (estado == EstadoDelPermiso.sinPreguntar) {
    return 'Todavía no se le pidió permiso para enviarle avisos.';
  }
  if (!hayToken) {
    return 'Hay permiso pero el teléfono no consiguió su dirección. Suele ser '
        'falta de conexión: se resuelve solo en el próximo arranque.';
  }
  if (!registrado) {
    return 'El teléfono tiene su dirección pero no llegó a registrarse en el '
        'servidor. Se reintenta en el próximo inicio de sesión.';
  }
  return 'Todo en orden: esta persona puede recibir avisos en este teléfono.';
}
