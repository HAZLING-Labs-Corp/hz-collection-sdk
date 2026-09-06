import 'dart:async';

import '../api_client.dart';
import '../remote_config.dart';
import '../transmision/huella_local.dart';

/// CADA CUÁNTO MIDE UN MÓDULO.
///
/// No es un detalle de implementación: es la mitad de lo que el comercio compra. Un
/// prestamista quiere una foto al dar de alta; una operadora quiere la calidad de red en el
/// tiempo; un reparto quiere saber dónde está el repartidor *ahora*. No es más dato ni menos
/// — es otro reloj, y cada uno cuesta distinto en batería y en tráfico.
/// 🔴 HOY LA CADENCIA ES UNA DECLARACIÓN, NO UN COMPORTAMIENTO. Nadie la lee: no hay un
/// `switch` sobre este enum en ningún lado, ni un `Timer`, ni un planificador. La única
/// invocación de los módulos es `alIniciarSesion`, así que **todos miden en cada inicio de
/// sesión**, cualquiera sea la cadencia que declaren. Verificado el 2026-09-01.
///
/// Se deja escrito en vez de borrarse porque la intención es correcta y sigue siendo el
/// diseño buscado — pero mientras no haya planificador, esto describe lo que se QUIERE, no
/// lo que pasa. Quien confíe en «una sola vez» va a medir en cada login.
///
/// El único freno real del SDK vive fuera de este mecanismo: las seis horas de
/// `Ubicacion.minimoEntreLecturas`, aplicadas a mano.
enum Cadencia {
  /// La intención: una sola vez, al darse de alta. Un perfil del aparato para un puntaje.
  /// Hoy, en la práctica: en cada inicio de sesión.
  episodica,

  /// Al abrir la aplicación, con un freno para no repetir. La ubicación aproximada.
  periodica,

  /// Cuando pasa algo. Los avisos: llegó, se abrió, se descartó.
  evento,

  /// En segundo plano, continuo. 🔴 Nivel 3: Google lo revisa a mano y puede rechazarlo.
  continua,
}

/// CUÁNTA FRICCIÓN LE PONE A LA PERSONA — y por eso, cuánto cuesta.
///
/// 🔴 El nivel no es una etiqueta: es el techo de cuánta gente va a aceptar. Y hay un límite
/// que ninguna configuración salta — los permisos de Android se declaran al COMPILAR, dentro
/// del manifest. La consola puede apagar cualquier módulo, pero **sólo puede prender los que
/// el APK ya declaró**.
class Nivel {
  /// Sin permiso. Marca, modelo, batería, espacio libre, tipo de red. Se tiene siempre.
  static const sinPermiso = 0;

  /// Permiso simple: un diálogo que se acepta o no. Avisos, ubicación aproximada.
  static const permisoSimple = 1;

  /// Permiso caro: aparece en la ficha de la tienda y baja las instalaciones.
  /// Contactos, calendario, ubicación precisa.
  static const permisoCaro = 2;

  /// Revisión manual de Google, con video justificando el uso. Ubicación en segundo plano.
  static const revisionDeGoogle = 3;
}

/// LO QUE UN MÓDULO NECESITA DEL NÚCLEO — y nada más.
///
/// 🔴 Es a propósito que sea tan poco. Un módulo que recibe la fachada entera puede llamar a
/// cualquier cosa, y a la tercera versión ya nadie sabe quién llama a quién. Esto es el
/// contrato completo: quién es la persona, cómo hablarle al servidor, y qué dijo el servidor
/// de este módulo.
class Contexto {
  const Contexto({
    required this.api,
    required this.instalacionId,
    required this.sujetoId,
    required this.config,
    this.portero,
  });

  /// Para hablarle al servicio. Ya trae la llave y el comercio resueltos.
  final AkPushApi api;

  /// El aparato. Existe desde que arranca la aplicación, aun sin persona.
  final String instalacionId;

  /// Quién entró. **Nulo si todavía no entró nadie** — y eso es normal: la instalación
  /// nace antes que el sujeto.
  final String? sujetoId;

  /// Lo que el servidor dijo de este comercio, incluido qué módulos activó.
  final AkPushConfig? config;

  /// QUIÉN DECIDE SI ESTA MEDICIÓN SE MANDA O SE CALLA.
  ///
  /// 🔴 Es opcional y por omisión no está, y eso es deliberado: sin portero, un módulo
  /// **manda siempre**, que es exactamente lo que hacían los tres módulos antes de que
  /// existiera la política. Un `Contexto` armado en una prueba vieja sigue comportándose
  /// igual que antes sin tocar la prueba.
  ///
  /// Con portero, el módulo pregunta antes de hablar y se ahorra la llamada cuando lo que
  /// midió es idéntico a lo último que mandó. Ver `politica_de_transmision.dart`.
  final PorteroDeEnvio? portero;
}

/// CÓMO SALIÓ UNA MEDICIÓN: si se mandó, si no hizo falta, o si se rompió algo.
///
/// Los tres estados son distintos y confundirlos es lo que ya costó una tarde: hasta el
/// 2026-09-01 «el servicio lo descartó» y «se guardó» se veían iguales, y el diagnóstico
/// afirmaba que todo andaba mientras del otro lado no quedaba nada.
class ResultadoDeMedicion {
  const ResultadoDeMedicion({
    required this.midio,
    required this.transmitio,
    required this.detalle,
    this.problema,
    this.campos = 0,
  });

  /// Si la medición se pudo tomar. Es lo que dice si el módulo está vivo.
  final bool midio;

  /// Si además salió por la red. `false` con [problema] en nulo NO es un fallo: es la
  /// política diciendo que no hacía falta.
  final bool transmitio;

  /// Una línea legible de qué pasó, para el diagnóstico.
  final String detalle;

  /// Por qué salió mal, si salió mal. `null` cuando todo está en orden.
  final String? problema;

  /// 🔴 CUÁNTOS CAMPOS SE MIDIERON — no cuántos se transmitieron.
  ///
  /// Son dos cosas distintas y hace falta la primera: la política puede decidir con toda razón
  /// que no hay nada nuevo que mandar, y eso NO significa que el barrido haya quedado corto.
  /// Sin este número, «midió bien y no hizo falta transmitir» y «el canal nativo devolvió un
  /// mapa vacío» se ven iguales desde afuera — y el segundo es el que hay que reintentar.
  final int campos;
}

/// MANDA LA MEDICIÓN, O SE LA CALLA — el único lugar donde se decide, para los tres módulos.
///
/// 🔴 Está acá y no en cada módulo porque son tres módulos y la decisión es una sola. Con
/// esto en cada uno, el cuarto que se escriba mañana se va a olvidar de preguntar y va a
/// mandar siempre, sin que nada lo delate salvo la factura.
///
/// Sin [Contexto.portero] se comporta **exactamente como antes**: mide y manda. Ver la nota
/// de ese campo.
Future<ResultadoDeMedicion> enviarMedicion(
  Contexto c,
  String modulo,
  Map<String, Object?> medido,
) async {
  final id = c.sujetoId;
  if (id == null) {
    return const ResultadoDeMedicion(
        midio: false, transmitio: false, detalle: 'todavía no entró nadie');
  }
  if (medido.isEmpty) {
    return const ResultadoDeMedicion(
      midio: false,
      transmitio: false,
      detalle: 'el sistema no devolvió ninguna medición',
      problema: 'el sistema no devolvió ninguna medición',
    );
  }

  final portero = c.portero;
  if (portero != null) {
    final decision = await portero.decidir(modulo: modulo, medido: medido);
    if (!decision.mandar) {
      // Midió bien; simplemente no había nada nuevo que contar. NO es un problema, y por
      // eso `problema` queda en nulo: marcarlo como fallo haría que el diagnóstico muestre
      // en rojo el caso que la política viene a buscar.
      return ResultadoDeMedicion(
        midio: true,
        transmitio: false,
        detalle: 'no se transmitió: ${decision.porQue}',
        campos: medido.length,
      );
    }
  }

  final descartadoPorQue = await c.api.reportarSenales(
    sujetoId: id,
    instalacionId: c.instalacionId,
    modulo: modulo,
    senales: medido,
  );

  // 🔴 UN 200 NO ES UN «SE GUARDÓ». El servicio acepta y descarta cuando el comercio tiene
  // el módulo apagado, y lo dice en el cuerpo. Si se descartó, la huella NO se anota: hacerlo
  // haría creer que el servidor tiene algo que no tiene, y ese campo no se volvería a mandar
  // hasta la resincronización de los siete días.
  if (descartadoPorQue != null) {
    return ResultadoDeMedicion(
      midio: true,
      transmitio: false,
      detalle: 'el servicio no lo guardó: $descartadoPorQue',
      problema: 'el servicio no lo guardó: $descartadoPorQue',
      campos: medido.length,
    );
  }

  await portero?.anotarQueLlego(modulo: modulo, medido: medido);
  return ResultadoDeMedicion(
    midio: true,
    transmitio: true,
    detalle: 'transmitido: ${medido.length} campos',
    campos: medido.length,
  );
}

/// CÓMO ESTÁ UN MÓDULO — para el diagnóstico, en castellano.
///
/// Existe porque los módulos se tragan sus fallos a propósito: perder una medición cuesta un
/// dato, que falle el arranque cuesta que esa persona no reciba nada. Pero ese silencio dejó
/// sin pistas a quien integra más de una vez. Acá el silencio queda registrado.
class EstadoDeModulo {
  const EstadoDeModulo({
    required this.andando,
    this.detalle,
    this.ultimoMotivo,
    this.ultimaVez,
  });

  /// Si el módulo está haciendo lo suyo hoy.
  final bool andando;

  /// Una línea que se pueda leer. «última hace 3 min», «sin permiso».
  final String? detalle;

  /// Por qué NO está andando. `null` si anda bien.
  final String? ultimoMotivo;

  /// Cuándo hizo lo suyo por última vez.
  final DateTime? ultimaVez;

  static const bien = EstadoDeModulo(andando: true);
}

/// UN MÓDULO DE COLLECTION.
///
/// ══ POR QUÉ EXISTE ESTE CONTRATO ══
///
/// Antes cada módulo se enchufaba a mano en la fachada: la ubicación le agregó siete métodos
/// estáticos, un campo, una política, tres líneas en el diagnóstico y dos en el inicio de
/// sesión. Medido el 2026-08-31, la fachada quedó en **1.498 líneas nombrando a cada módulo
/// una por una, 23 veces**. Agregar «batería» significaba volver a editar ese archivo. Cada
/// vez, y con el riesgo de romper los avisos, que viven ahí al lado.
///
/// Con esto, agregar un módulo es **escribir un archivo y sumarlo al registro**. La fachada
/// no lo nombra nunca.
///
/// ══ LO QUE UN MÓDULO PROMETE ══
///
/// 🔴 **Nunca tumba nada.** Todos los ganchos se llaman dentro de un try/catch del registro,
/// pero un módulo que se cuelga para siempre bloquea a los que siguen: cada gancho tiene que
/// terminar, con su propio tope de tiempo si hace algo que puede esperar.
///
/// 🔴 **No pide permisos por su cuenta en el arranque.** Pedirlos es una decisión de producto
/// —cuándo, con qué palabras, después de qué— y la toma el comercio desde la consola. El
/// módulo expone qué necesita y espera a que lo manden.
///
/// 🔴 **No sabe de los otros módulos.** Si dos se necesitan, se hablan por el servidor, no
/// por adentro.
abstract class Modulo {
  /// Cómo se llama en el catálogo y en la configuración del servidor. En minúsculas y sin
  /// espacios: `avisos`, `ubicacion`, `aparato`.
  String get nombre;

  /// Cuánta fricción cuesta. Ver [Nivel].
  int get nivel;

  /// Cada cuánto mide.
  Cadencia get cadencia;

  /// Cuántos campos entregó su última medición.
  ///
  /// 🔴 Existe para poder distinguir «corrió» de «corrió y trajo algo». Un módulo cuyo canal
  /// nativo devuelve un mapa vacío no lanza ninguna excepción: se ve exactamente igual que uno
  /// que anduvo bien. Sin este número, la fachada no tiene forma de saber que el barrido quedó
  /// corto, y era la causa de que dos personas quedaran con el bloque básico para siempre.
  int get camposDelUltimoBarrido => 0;

  /// Los permisos de Android que necesita, con su nombre completo. Vacío para el nivel 0.
  ///
  /// Se declara acá **para poder decirlo**, no para pedirlo: sirve para que la consola
  /// muestre en gris lo que el APK no trae, y para armar el manual del comercio.
  List<String> get permisos => const [];

  /// Cuando arranca la aplicación. Todavía puede no haber nadie logueado.
  Future<void> alIniciar(Contexto c) async {}

  /// Cuando alguien inicia sesión. Es donde miden los de cadencia episódica.
  Future<void> alEntrar(Contexto c) async {}

  /// Cuando la persona sale. Lo que sea de ella se olvida; lo del aparato se queda.
  Future<void> alSalir(Contexto c) async {}

  /// Cómo está. Sale en el diagnóstico.
  Future<EstadoDeModulo> estado(Contexto c) async => EstadoDeModulo.bien;
}
