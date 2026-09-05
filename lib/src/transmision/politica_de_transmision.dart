/// LA POLÍTICA DE TRANSMISIÓN — cuándo se mide, cuándo se manda, y qué se descarta.
///
/// ══ QUÉ HABÍA ANTES DE ESTE ARCHIVO ══
///
/// El SDK **medía y mandaba en el mismo acto**, siempre, sin preguntarse si lo que medía era
/// distinto de lo que ya había mandado. Medido en el emulador el 2026-09-04, con el
/// simulador del servicio contando peticiones: **cinco llamadas de red por sesión**, de las
/// cuales dos eran mediciones —3.096 bytes— que en la segunda y la tercera sesión decían
/// exactamente lo mismo que en la primera. La política no existía; existía el envío.
///
/// ══ LAS CINCO DECISIONES, Y EL NÚMERO DE CADA UNA ══
///
///  1. **Cuándo se mide.** Al abrir la aplicación, seguro. No cambia: es lo que ya hacía.
///  2. **Cuándo se transmite.** 🔴 Nunca en el mismo momento de medir. Lo que se mide se
///     guarda en el teléfono y sale **por lote, al abrir**. Una llamada de red por medición
///     se nota en la batería, y en un teléfono de gama baja con red de datos se nota mucho.
///  3. **Qué dispara un envío.** Sólo un cambio real — ver [SENALES_DE_MOMENTO], que es
///     donde está la trampa.
///  4. **Sin conexión.** Se acumula con tope, y se descarta lo más viejo. Ver [topeDeEventos].
///  5. **Resincronización.** Todo igual cada [resincronizarCadaDias] días, aunque no haya
///     cambiado nada.
///
/// ══ 🔴 LA TRAMPA, MEDIDA Y DOCUMENTADA DEL OTRO LADO ══
///
/// De las 105 señales, **diez cambian en cada medición**: la hora local cambia cada segundo
/// y la temperatura de la batería cada minuto. Si entran en la comparación, el delta nunca
/// está vacío y «mandá sólo lo que cambió» manda *siempre todo*. El sistema parecería andar
/// bien; sólo sería caro. Es el tipo de error que no da ningún síntoma hasta la factura.
///
/// La lista sale de `SENALES_DE_MOMENTO` en `escritura-a-destino.service.ts` del back, donde
/// ya estaba identificada y probada. **Está copiada acá y eso es una segunda lista**, que es
/// exactamente lo que este repositorio evita en todos lados — pero no hay forma de que Dart
/// lea un `const` de TypeScript, y la alternativa (que el servidor la sirva) obliga a un
/// cambio del otro lado que esta noche no me corresponde hacer. Queda [senalesDeMomentoDe]
/// preparado para leerla de la configuración el día que el servidor la mande, y mientras
/// tanto una prueba fija los diez nombres para que nadie los cambie de un solo lado.
library;

/// Las señales que son un INSTANTE y no un estado. No se comparan nunca.
///
/// Copiada literal de `SENALES_DE_MOMENTO` del back (2026-09-04). Se compara por el nombre
/// completo y no por prefijo: dentro de `bat_` hay estados (`bat_salud`) y momentos
/// (`bat_voltaje_mv`), así que un prefijo dejaría afuera cosas que sí importan.
const Set<String> senalesDeMomento = {
  'hd_hora_local',
  'hd_dia_de_semana',
  'ent_pantalla_encendida',
  'ent_nivel_de_senal',
  'bat_temperatura_decimas_c',
  'bat_voltaje_mv',
  'red_bajada_kbps',
  'red_subida_kbps',
  'cfg_boot_count',
  // El único de los cinco campos de ubicación que lo es: la coordenada es un estado —dónde
  // está la persona— y su marca de tiempo es un instante. Ver el comentario largo del back.
  'ubicacion_cuando',
};

/// 🔴 LOS DOS QUE FALTAN EN LA LISTA DEL BACK, ENCONTRADOS MIDIENDO — 2026-09-04
///
/// Están aparte de [senalesDeMomento] y no mezclados adentro **a propósito**: aquélla es la
/// copia literal de lo que el back declara hoy, y una prueba la compara nombre por nombre.
/// Ésta es lo que este lado encontró de más y que el back todavía no tiene.
///
/// Cómo aparecieron: con el delta ya andando, una sesión sin tocar nada seguía transmitiendo
/// las 105 señales. El panel de la aplicación de ejemplo lo dijo con todas las letras —
/// *«senales: cambiaron 1 campos: hd_ram_libre_mb»*—. **Un solo campo alcanzaba para anular
/// el mecanismo entero**: 3 KB por sesión, en todos los teléfonos, para informar que la
/// memoria libre pasó de un tramo de 256 MB al de al lado.
///
/// Que son momentos no es una opinión: sus propias fichas en `campos.dart` lo dicen —
/// «cuánta memoria tenía libre **al medir**» y «si el sistema estaba quedándose sin memoria
/// **al medir**»—. Un valor cuya definición incluye «al medir» es un instante, no un estado.
///
/// 📌 **HAY QUE AVISARLE AL BACK, Y NO CAMBIARLO YO SOLO.** Del otro lado, `SENALES_DE_MOMENTO`
/// alimenta la escritura a destinos y la serie de `mediciones__<slug>`: mientras estos dos no
/// estén allá, el back va a escribir una fila de serie por sesión y por persona que dice
/// «cambió la memoria libre», que es ruido puro con el costo de una escritura.
const Set<String> momentosQueElBackTodaviaNoTiene = {
  'hd_ram_libre_mb',
  'hd_ram_en_las_ultimas',
};

/// Lo mismo, pero para el módulo `aparato`, que usa OTROS nombres.
///
/// 🔴 No está en la lista del back y es a propósito: el back nombra las 105 señales del
/// módulo `senales`, y `aparato` manda seis campos con nombres propios (`bateria`,
/// `espacioLibreMb`). Cuatro de esos seis se mueven en cada apertura —el nivel de batería
/// cambia por definición— así que sin declararlos, `aparato` dispararía un envío siempre y
/// la política valdría para dos módulos de tres.
///
/// `red`, `sistema` y `espacioTotalMb` NO están: que alguien pase de wifi a datos es un
/// cambio de verdad, y un envío por eso es un envío que informa algo.
const Set<String> momentosDelAparato = {
  'bateria',
  'cargando',
  'espacioLibreMb',
  'espacioLibrePorciento',
};

/// Qué es momento en cada módulo. Un módulo que no esté acá no tiene ninguno —
/// `autenticidad` son cinco booleanos sobre el aparato y ninguno se mueve solo.
Set<String> senalesDeMomentoDe(String modulo) => switch (modulo) {
      'senales' => {...senalesDeMomento, ...momentosQueElBackTodaviaNoTiene},
      'aparato' => momentosDelAparato,
      _ => const <String>{},
    };

/// Los números de la política. Todos con su motivo, porque un número sin motivo es un
/// número que el que venga después va a cambiar por otro igual de arbitrario.
class PoliticaDeTransmision {
  const PoliticaDeTransmision({
    this.soloSiCambio = true,
    this.resincronizarCadaDias = 7,
    this.topeDeEventos = 1000,
    this.topeDeBytes = 512 * 1024,
    this.topeDeLote = 250,
    this.sesionMuertaTrasMinutos = 30,
  });

  /// 🔴 CÓMO SE VUELVE AL COMPORTAMIENTO DE ANTES, EN UNA LÍNEA.
  ///
  /// Existe porque la regla de la noche es que nada de lo que hoy anda puede dejar de andar,
  /// y «medir y mandar siempre» es lo que hoy anda. Si mañana aparece un comercio para el
  /// que el delta no sirve —una auditoría que necesita una fila por apertura, por ejemplo—,
  /// se le pone esto y queda como estaba, sin tocar una línea del resto.
  static const comoEstabaAntes = PoliticaDeTransmision(soloSiCambio: false);

  static const porOmision = PoliticaDeTransmision();

  /// Si una medición idéntica a la anterior se manda igual. `false` es el comportamiento
  /// viejo: se manda siempre.
  final bool soloSiCambio;

  /// 🔴 SIETE DÍAS, Y ES MÁS SEGUIDO QUE LOS TREINTA DE LOS DESTINOS A PROPÓSITO.
  ///
  /// Un destino de terceros se puede volver a llenar desde nuestra base cuando haga falta:
  /// el dato sigue acá. **Un agujero en la serie propia no se recupera de ninguna otra
  /// forma** — si un lote se pierde y el delta cree que ya lo mandó, ese día no existe para
  /// siempre. Siete días es el techo de cuánto puede durar un agujero así.
  ///
  /// El costo de tenerlo bajo es una llamada de ~3 KB por semana por teléfono. Bajarlo a
  /// uno costaría siete veces eso para tapar un agujero que casi nunca ocurre; subirlo a
  /// treinta dejaría un mes de serie muerta cuando ocurre.
  final int resincronizarCadaDias;

  /// 🔴 MIL EVENTOS. De dónde sale el número:
  ///
  /// Una sesión con una solicitud llena entera son ~30 eventos: abrir y cerrar, el
  /// formulario, y dos por cada campo. Mil eventos son entonces **más de un mes de uso
  /// diario sin ver la red ni una vez**, que es más de lo que aguanta cualquier escenario
  /// real —y en Venezuela, que es donde esto se usa, «sin red» se mide en días, no en meses.
  ///
  /// El tope de verdad no es éste sino [topeDeBytes]: en Android esto vive en
  /// `SharedPreferences`, que es un XML que el sistema **carga entero en memoria** la
  /// primera vez que alguien lo toca. Mil eventos son ~120 KB; el freno de 512 KB corta
  /// mucho antes de que ese archivo empiece a pesar en el arranque.
  final int topeDeEventos;

  /// El otro freno, el que de verdad protege: medio megabyte de cola. Ver [topeDeEventos].
  final int topeDeBytes;

  /// Cuántos eventos entran en UNA petición. Doscientos cincuenta son ~30 KB.
  ///
  /// 🔴 No es lo mismo que [topeDeEventos] y confundirlos sería caro. Ése es cuánto se
  /// puede acumular; éste es cuánto sale por vez. Después de dos semanas sin red la cola
  /// puede tener mil eventos, y un cuerpo de 120 KB sobre una red de datos venezolana es
  /// una petición que falla — y falla entera, así que no avanzaría nunca. En lotes, lo que
  /// llegó queda del otro lado y el resto se reintenta.
  final int topeDeLote;

  /// 🔴 SE DESCARTA EL MÁS VIEJO, Y NO ES LA ELECCIÓN OBVIA — HAY QUE EXPLICARLA.
  ///
  /// La alternativa era descartar los eventos de campo (`CAMPO_PEGADO`, `CAMPO_ESCRITO`),
  /// que son los más numerosos y los que menos valen de a uno, y quedarse con el esqueleto
  /// de sesiones y formularios. Se descartó por dos razones:
  ///
  ///  · **Sesga la serie sin dejar rastro.** Si se tiran unos tipos y no otros, «no pegó
  ///    nada» y «se tiró el evento de que pegó» quedan iguales del otro lado. Un modelo de
  ///    riesgo entrenado sobre eso aprende una mentira.
  ///  · **Descartar lo nuevo es peor todavía.** Un teléfono sin red congelaría la cola en
  ///    los primeros mil eventos y no volvería a registrar nada: la serie mostraría a una
  ///    persona que dejó de usar la aplicación justo el día que se quedó sin red. Es
  ///    activamente falso, no incompleto.
  ///
  /// Se descarta lo más viejo, entero, y **se cuenta**: cuántos se perdieron viaja en el
  /// `datos` del siguiente `SESION_ABRE`, así que del otro lado se sabe que hay un hueco y
  /// de qué tamaño, en vez de tener que adivinarlo.
  bool get descartaLoMasViejo => true;

  /// Cuánto silencio convierte una vuelta a la aplicación en una sesión NUEVA.
  ///
  /// Treinta minutos es lo que usa la industria desde que existe la analítica web, y el
  /// motivo sigue valiendo: mirar la hora en medio de una sesión no es cerrar la
  /// aplicación, y contar dos sesiones ahí inventa un patrón de uso que no existe. Volver
  /// al día siguiente sí es otra sesión.
  final int sesionMuertaTrasMinutos;
}

/// LO QUE SE DECIDIÓ SOBRE UNA MEDICIÓN, con el motivo en castellano.
///
/// El motivo no es decoración: sin él, «no se mandó» y «no se pudo mandar» se ven iguales en
/// el diagnóstico, y son dos problemas opuestos. Ya pasó una vez con las señales que el
/// servicio descartaba en silencio (ver `reportarSenales`), y costó una tarde.
class DecisionDeEnvio {
  const DecisionDeEnvio({
    required this.mandar,
    required this.porQue,
    this.camposQueCambiaron = const [],
  });

  final bool mandar;
  final String porQue;

  /// Cuáles cambiaron. Sólo los nombres — nunca los valores, que son datos de la persona.
  final List<String> camposQueCambiaron;
}

/// EL DELTA, PURO Y SIN DISCO — para poder probarlo sin un teléfono.
///
/// Devuelve qué campos cambiaron respecto de [huellaAnterior], **ignorando los momentos**.
/// [huellaAnterior] es `nombre → hash`, nunca `nombre → valor`: guardar los valores sería
/// tener una segunda copia de los datos de la persona en el teléfono, y una de las dos
/// envejece. Con el hash alcanza para contestar la única pregunta que hay que contestar.
DecisionDeEnvio decidirEnvio({
  required String modulo,
  required Map<String, Object?> medido,
  required Map<String, String> huellaAnterior,
  required DateTime? ultimaResincronizacion,
  required DateTime ahora,
  PoliticaDeTransmision politica = PoliticaDeTransmision.porOmision,
}) {
  if (!politica.soloSiCambio) {
    return const DecisionDeEnvio(mandar: true, porQue: 'la política manda siempre');
  }
  if (medido.isEmpty) {
    return const DecisionDeEnvio(mandar: false, porQue: 'no hay nada medido');
  }
  if (huellaAnterior.isEmpty) {
    return const DecisionDeEnvio(
        mandar: true, porQue: 'primera medición de este módulo en este teléfono');
  }

  // La resincronización va ANTES del delta, no después: el sentido de resincronizar es
  // mandar aunque el delta diga que no hace falta. Preguntarlo al revés lo dejaría sin efecto
  // justo en el caso que existe para cubrir.
  if (ultimaResincronizacion == null ||
      ahora.difference(ultimaResincronizacion).inDays >= politica.resincronizarCadaDias) {
    return DecisionDeEnvio(
      mandar: true,
      porQue: 'resincronización: pasaron ${politica.resincronizarCadaDias} días o más',
    );
  }

  final momentos = senalesDeMomentoDe(modulo);
  final cambiaron = <String>[];
  for (final e in medido.entries) {
    if (momentos.contains(e.key)) continue;
    if (huellaAnterior[e.key] != huellaDelValor(e.value)) cambiaron.add(e.key);
  }

  // 🔴 Un campo que DESAPARECIÓ también es un cambio. Que el teléfono deje de devolver
  // `acc_servicios_activos` dice algo —el fabricante lo cerró, el sistema se actualizó— y
  // sin esta vuelta, la huella lo daría por vigente para siempre.
  for (final nombre in huellaAnterior.keys) {
    if (momentos.contains(nombre)) continue;
    if (!medido.containsKey(nombre)) cambiaron.add(nombre);
  }

  if (cambiaron.isEmpty) {
    return const DecisionDeEnvio(
      mandar: false,
      porQue: 'nada cambió desde la última vez (los momentos no cuentan)',
    );
  }
  cambiaron.sort();
  return DecisionDeEnvio(
    mandar: true,
    porQue: 'cambiaron ${cambiaron.length} campos: ${cambiaron.take(5).join(", ")}'
        '${cambiaron.length > 5 ? "…" : ""}',
    camposQueCambiaron: cambiaron,
  );
}

/// La huella de un valor: FNV-1a de 32 bits, en hexadecimal.
///
/// 🔴 NO ES CRIPTOGRÁFICO Y NO TIENE QUE SERLO. La única pregunta que contesta es «¿esto
/// cambió?». Se escribe a mano en vez de sumar el paquete `crypto` por dos razones: una
/// dependencia del SDK se la come **toda aplicación que lo instale**, y `String.hashCode` de
/// Dart no está garantizado estable entre arranques ni entre versiones — y una huella que
/// cambia sola haría que todo se retransmita en cada apertura, que es justo lo que esto
/// viene a evitar.
///
/// Treinta y dos bits sobre ~105 campos: que dos valores distintos del MISMO campo choquen
/// es del orden de una vez cada cuatro mil millones, y cuando pasa cuesta una transmisión
/// que no se hizo — que la resincronización de los siete días tapa. Es el peor caso, y es
/// barato.
///
/// El `null` se distingue de la cadena vacía y del texto «null» a propósito: que un campo
/// deje de venir es un cambio, y confundirlo con un valor vacío lo escondería.
String huellaDelValor(Object? v) {
  final texto = v == null ? ' nulo' : v.toString();
  var h = 0x811c9dc5; // el desplazamiento inicial de FNV-1a de 32 bits
  for (final unidad in texto.codeUnits) {
    h ^= unidad & 0xff;
    if (unidad > 0xff) h ^= (unidad >> 8) & 0xff;
    // Multiplicar por el primo 16777619 quedándose en 32 bits. Se hace con sumas de
    // desplazamientos y no con `*`: el producto de 32 por 24 bits se pasa del entero exacto
    // que admite JavaScript, y ahí el resultado dejaría de coincidir con el de la máquina
    // virtual — o sea, la misma medición daría huellas distintas según dónde corra.
    h = (h + (h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24)) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// La huella de una medición entera: `nombre → hash`. Los momentos se guardan igual, para
/// poder decir después qué valor tenían — pero no se comparan. Ver [decidirEnvio].
Map<String, String> huellaDe(Map<String, Object?> medido) =>
    medido.map((k, v) => MapEntry(k, huellaDelValor(v)));
