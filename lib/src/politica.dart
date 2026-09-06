/// La política de notificaciones que el comercio configura desde su consola.
///
/// ## Por qué esto existe
///
/// Cuándo pedirle el permiso a una persona no es una decisión del programador que
/// integra el SDK: es del comercio, y cambia con el negocio. Una app de banca
/// puede querer pedirlo apenas la persona entra —porque sus avisos son de
/// seguridad y nadie discute que los quiere—, y una de comercio conviene que
/// espere a la primera compra.
///
/// Hoy eso está escrito en el código de cada aplicación, así que cambiarlo
/// significa publicar una versión nueva. Sirviéndolo con la configuración, el
/// comercio lo cambia desde su consola y toma efecto en el siguiente arranque.
///
/// ## 🔴 Lo que «obligatorio» NO puede significar
///
/// Ningún SDK puede obligar a nadie a aceptar notificaciones. El diálogo es del
/// sistema operativo y la respuesta es de la persona; no hay API que lo fuerce, y
/// la que lo intentara sería rechazada por las tiendas.
///
/// Acá `obligatorio` significa una cosa concreta y más chica: **el SDK le avisa a
/// la aplicación que este comercio considera el permiso indispensable**, para que
/// la aplicación insista —una pantalla que explique, un aviso que no se cierra, lo
/// que decida—. Lo que hace con esa señal es de la aplicación. El SDK informa; no
/// bloquea pantallas ajenas.
///
/// Prometer más que eso sería prometer algo que no se puede cumplir, y se
/// descubriría en la primera integración.
library;

import 'permiso.dart';

/// En qué momento el SDK pide el permiso del sistema.
enum MomentoDelPermiso {
  /// Apenas arranca la aplicación. Es lo que hace hoy el SDK y lo que hace la
  /// app de la que nos copiamos, así que es el valor por defecto: un comercio
  /// que no configure nada no ve ningún cambio.
  ///
  /// Es también el peor momento en términos de aceptación —la persona todavía no
  /// sabe qué hace la app— pero cambiarlo por su cuenta sería cambiarle el
  /// comportamiento a quien ya integró sin que lo pidiera.
  arranque,

  /// Cuando la persona inicia sesión, en `identify()`. Para entonces ya sabe qué
  /// es la aplicación y qué esperar de ella.
  login,

  /// El SDK no pide nada solo: espera a que la aplicación llame a
  /// `pedirPermiso()` en el momento que le parezca. Es el que más convierte y el
  /// que más trabajo le da a quien integra.
  laAppDecide,
}

/// Los textos de la pregunta blanda. Son del comercio, no nuestros: hablan con su
/// voz y de su negocio, y por eso viajan con la configuración en vez de estar
/// escritos en el paquete.
class TextosDeLaPregunta {
  const TextosDeLaPregunta({
    required this.titulo,
    required this.cuerpo,
    required this.aceptar,
    required this.ahoraNo,
  });

  final String titulo;
  final String cuerpo;
  final String aceptar;
  final String ahoraNo;

  static const predeterminados = TextosDeLaPregunta(
    titulo: '¿Te avisamos?',
    cuerpo: 'Podemos avisarte cuando haya algo importante en tu cuenta.',
    aceptar: 'Sí, avísenme',
    ahoraNo: 'Ahora no',
  );

  factory TextosDeLaPregunta.fromJson(Map<String, dynamic> json) =>
      TextosDeLaPregunta(
        titulo: json['titulo'] as String? ?? predeterminados.titulo,
        cuerpo: json['cuerpo'] as String? ?? predeterminados.cuerpo,
        aceptar: json['aceptar'] as String? ?? predeterminados.aceptar,
        ahoraNo: json['ahoraNo'] as String? ?? predeterminados.ahoraNo,
      );

  Map<String, dynamic> toJson() => {
        'titulo': titulo,
        'cuerpo': cuerpo,
        'aceptar': aceptar,
        'ahoraNo': ahoraNo,
      };
}

/// Lo que el comercio decidió sobre las notificaciones en su aplicación.
class PoliticaDeNotificaciones {
  const PoliticaDeNotificaciones({
    this.momento = MomentoDelPermiso.arranque,
    this.obligatorio = false,
    this.preguntaBlanda = false,
    this.reintentarCadaDias = 7,
    this.textos = TextosDeLaPregunta.predeterminados,
  });

  final MomentoDelPermiso momento;

  /// El comercio considera el permiso indispensable. Ver la nota de la cabecera
  /// sobre lo que esto puede y no puede significar.
  final bool obligatorio;

  /// Si la aplicación tiene que mostrar su propia pantalla ANTES del diálogo del
  /// sistema.
  ///
  /// Es lo que convierte un «no» irreversible en un «ahora no» reversible: en
  /// iPhone el diálogo del sistema se muestra una sola vez en la vida de la
  /// instalación, y en Android 13+ dos descartes lo dan por denegado. Un «ahora
  /// no» en una pantalla propia no gasta ese único intento.
  final bool preguntaBlanda;

  /// Cuántos días esperar antes de volver a mostrar la pregunta blanda a quien
  /// dijo «ahora no». Cero significa preguntar en cada arranque, que es cómo se
  /// consigue que alguien desinstale la aplicación.
  final int reintentarCadaDias;

  final TextosDeLaPregunta textos;

  /// La política que rige cuando el servidor no manda ninguna.
  ///
  /// Reproduce exactamente lo que el SDK hace hoy: pedir el permiso en el
  /// arranque, sin pregunta blanda. Es deliberado — mientras el servicio no
  /// sirva el campo, nadie ve un cambio de comportamiento.
  static const comoEstabaAntes = PoliticaDeNotificaciones();

  /// Lee la política de la configuración del comercio.
  ///
  /// Tolera que el campo no exista: mientras el servicio no lo sirva, se usa
  /// [comoEstabaAntes]. Es lo que permite que el SDK traiga esto hoy sin esperar
  /// al servidor.
  factory PoliticaDeNotificaciones.fromJson(Map<String, dynamic>? json) {
    if (json == null) return comoEstabaAntes;
    return PoliticaDeNotificaciones(
      momento: _momentoDesde(json['momento'] as String?),
      obligatorio: json['obligatorio'] as bool? ?? false,
      preguntaBlanda: json['preguntaBlanda'] as bool? ?? false,
      reintentarCadaDias: (json['reintentarCadaDias'] as num?)?.toInt() ?? 7,
      textos: json['textos'] is Map
          ? TextosDeLaPregunta.fromJson(
              (json['textos'] as Map).cast<String, dynamic>())
          : TextosDeLaPregunta.predeterminados,
    );
  }

  Map<String, dynamic> toJson() => {
        'momento': momento.name,
        'obligatorio': obligatorio,
        'preguntaBlanda': preguntaBlanda,
        'reintentarCadaDias': reintentarCadaDias,
        'textos': textos.toJson(),
      };

  /// Un valor desconocido cae en el que ya andaba, y no rompe.
  ///
  /// Es a propósito: si mañana el servicio agrega un momento nuevo, una
  /// aplicación vieja tiene que seguir funcionando en vez de fallar al arrancar
  /// por una palabra que no conoce.
  static MomentoDelPermiso _momentoDesde(String? v) => switch (v) {
        'login' => MomentoDelPermiso.login,
        'laAppDecide' => MomentoDelPermiso.laAppDecide,
        _ => MomentoDelPermiso.arranque,
      };
}

/// Qué hay que hacer ahora con el permiso, según la política y lo que ya pasó.
///
/// Es una decisión pura: no toca el sistema operativo ni la red. Recibe el estado
/// y devuelve la acción, lo que la hace comprobable sin un teléfono — que es la
/// única forma de probar de verdad la parte que más importa.
enum AccionDePermiso {
  /// No hacer nada: ya está concedido, o no es el momento.
  ninguna,

  /// Mostrar la pantalla propia del comercio antes del diálogo del sistema.
  mostrarPreguntaBlanda,

  /// Disparar el diálogo del sistema.
  pedirAlSistema,

  /// Está denegado para siempre y el comercio lo considera indispensable: lo
  /// único que queda es ofrecer los Ajustes del teléfono.
  ofrecerAjustes,
}

/// Cuándo se está evaluando la decisión.
enum Disparador { arranque, login, laAppLoPidio }

/// Decide qué hacer, dada la política, el estado del permiso y cuándo se
/// preguntó por última vez.
///
/// [estado] es lo que reportó el sistema operativo. La función no lo consulta:
/// lo recibe. Por eso se puede probar entera sin un teléfono, que es justo la
/// parte que más importa de todo este módulo.
AccionDePermiso decidirQueHacer({
  required PoliticaDeNotificaciones politica,
  required Disparador disparador,
  required EstadoDelPermiso estado,
  required bool yaSePregunto,
  Duration? desdeLaUltimaPregunta,
}) {
  // Ya está: no hay nada que decidir. `provisional` de iOS también entrega, así
  // que tampoco hay nada que pedir.
  if (estado == EstadoDelPermiso.concedido ||
      estado == EstadoDelPermiso.provisional) {
    return AccionDePermiso.ninguna;
  }

  // Sin vuelta atrás desde la app. Sólo se ofrece si el comercio lo considera
  // indispensable; si no, insistir con los Ajustes es molestar por algo que la
  // persona ya contestó.
  if (estado.soloQuedanLosAjustes) {
    return politica.obligatorio
        ? AccionDePermiso.ofrecerAjustes
        : AccionDePermiso.ninguna;
  }

  // ¿Es el momento que el comercio eligió?
  //
  // 🔴 EL «ARRANQUE» SE RESCATA EN EL PRIMER LOGIN, Y SIN ESTO NO PEDÍA NUNCA.
  //
  // Medido el 2026-09-05, con Juan mirando su teléfono: entró como una persona del
  // núcleo y no le apareció ningún diálogo de permiso; tuvo que tocar la campanita.
  // La causa: `Disparador.arranque` no lo pasa NADIE en el SDK —el único que llama a
  // esta función es `planearInicioDeSesion`, siempre con `login`—, así que un comercio
  // con la política en «arranque» quedaba sin que se le pidiera el permiso jamás. La
  // única puerta era `init(pedirPermisoAlIniciar: true)`, que no pasa por acá y por lo
  // tanto ignora la pregunta blanda, el reintento y el «obligatorio».
  //
  // Una opción de la consola que no hace nada es peor que no tenerla: el comercio la
  // elige, la ve guardada, y su gente nunca recibe un aviso sin que nada falle.
  //
  // El rescate es angosto a propósito: **sólo si todavía no se preguntó NUNCA**. Si el
  // arranque ya preguntó, `yaSePregunto` es verdadero y acá no se vuelve a preguntar,
  // así que no puede producir dos diálogos. Y no se pide al arrancar en frío —que sigue
  // siendo el peor momento— sino al entrar, cuando la persona ya sabe qué es la app.
  final esElMomento = switch (politica.momento) {
    MomentoDelPermiso.arranque =>
      disparador == Disparador.arranque ||
          (disparador == Disparador.login && !yaSePregunto),
    MomentoDelPermiso.login => disparador == Disparador.login,
    MomentoDelPermiso.laAppDecide => disparador == Disparador.laAppLoPidio,
  };

  // Cuando la app lo pide explícitamente, se le hace caso siempre: pidió, y
  // negarse porque «no es el momento» sería desobedecer a quien integra.
  if (!esElMomento && disparador != Disparador.laAppLoPidio) {
    return AccionDePermiso.ninguna;
  }

  // A quien ya dijo «ahora no» se le respeta la espera. Preguntar en cada
  // arranque es cómo se consigue una desinstalación.
  if (yaSePregunto &&
      disparador != Disparador.laAppLoPidio &&
      politica.reintentarCadaDias > 0) {
    final espera = Duration(days: politica.reintentarCadaDias);
    if (desdeLaUltimaPregunta == null || desdeLaUltimaPregunta < espera) {
      return AccionDePermiso.ninguna;
    }
  }

  return politica.preguntaBlanda
      ? AccionDePermiso.mostrarPreguntaBlanda
      : AccionDePermiso.pedirAlSistema;
}


/// LOS TEXTOS DEL MODAL DE UBICACIÓN, TAL COMO LOS ESCRIBIÓ EL COMERCIO
///
/// Vienen de `/api/v1/configuracion`. Si el comercio no escribió nada, valen los de
/// abajo — que no son de relleno: están redactados para contestar las tres preguntas
/// que alguien se hace antes de decir que sí (¿qué tan preciso?, ¿cuándo?, ¿lo puedo
/// deshacer?), y las tres respuestas son verdad en este SDK.
class TextosDeUbicacion {
  const TextosDeUbicacion({
    this.titulo = 'Avisos de tu zona',
    this.cuerpo =
        'Si nos dejás saber en qué zona estás, te escribimos sólo lo que pasa cerca '
        'tuyo en vez de mandarte todo.',
    this.aceptar = 'Compartir mi zona',
    this.ahoraNo = 'Ahora no',
    this.motivos = const [
      'Es la zona, no la dirección exacta',
      'Sólo mientras usás la aplicación',
      'Lo cambiás cuando quieras desde los ajustes',
    ],
  });

  final String titulo;
  final String cuerpo;
  final String aceptar;
  final String ahoraNo;
  final List<String> motivos;

  /// Cada campo cae por separado en su valor por omisión.
  ///
  /// 🔴 A propósito: un comercio que sólo quiso cambiar el título no tiene por qué
  /// quedarse sin los tres motivos. Si esto fuera «o todo lo del servidor o todo lo de
  /// fábrica», el primero que edita una palabra se queda con el modal vacío.
  factory TextosDeUbicacion.fromJson(Map<String, dynamic>? j) {
    const d = TextosDeUbicacion();
    if (j == null) return d;
    String t(String k, String x) {
      final v = j[k];
      return (v is String && v.trim().isNotEmpty) ? v.trim() : x;
    }
    final m = j['motivos'];
    return TextosDeUbicacion(
      titulo: t('titulo', d.titulo),
      cuerpo: t('cuerpo', d.cuerpo),
      aceptar: t('aceptar', d.aceptar),
      ahoraNo: t('ahoraNo', d.ahoraNo),
      motivos: (m is List && m.isNotEmpty)
          ? m.map((e) => '$e').where((e) => e.trim().isNotEmpty).toList()
          : d.motivos,
    );
  }
}

/// CÓMO SE LEE LA UBICACIÓN: UNA VEZ AL ENTRAR, SEGUIDO, O SEGUIDO CON LA APP CERRADA.
///
/// ══ 🔴 SON TRES COSAS DISTINTAS Y CUESTAN DISTINTO ══
///
/// No es «más o menos seguido» del mismo mecanismo: cada modo exige otro permiso, otra
/// pregunta a la persona y otro trámite en la tienda. Elegir mal acá es la diferencia
/// entre una función que anda y una aplicación que Google saca de Play.
///
/// El pedido que trajo esto (Juan, 2026-09-05) es el vendedor de motos: *«yo quiero saber
/// qué tanto se mueve en el día, y no necesariamente con la aplicación abierta… le digo
/// instalá la aplicación y esperá quince días»*. Eso es [enSegundoPlano]. Los otros dos
/// modos no lo contestan, y decir que sí lo hacen sería mentir.
enum ModoDeLectura {
  /// UNA LECTURA CUANDO LA PERSONA ABRE LA APLICACIÓN, con el freno de
  /// [Ubicacion.minimoEntreLecturas]. **Es lo de siempre y es el valor por omisión**:
  /// nadie cambia de comportamiento por actualizar el paquete.
  ///
  /// Permiso: `ACCESS_COARSE_LOCATION`, el que ya se pedía. Nada nuevo.
  alEntrar,

  /// LECTURAS SEGUIDAS MIENTRAS LA PERSONA USA LA APLICACIÓN, sin el freno de las dos
  /// horas. Se corta sola cuando la aplicación se va al fondo y vuelve a arrancar cuando
  /// vuelve al frente.
  ///
  /// Permiso: **ninguno nuevo**. El mismo `ACCESS_COARSE_LOCATION`.
  ///
  /// 🔴 Aporta poco al «cuánto se mueve» —nadie cruza la ciudad en los tres minutos que
  /// dura una sesión— pero es gratis y sirve para precisión: quien abre la aplicación tres
  /// veces en una mañana deja tres marcas en vez de una. No confundirlo con el de abajo.
  enPrimerPlano,

  /// LECTURAS SEGUIDAS CON LA APLICACIÓN EN EL FONDO. Es lo que contesta «cuánto se mueve
  /// en el día».
  ///
  /// Permiso: `ACCESS_BACKGROUND_LOCATION` **+ `FOREGROUND_SERVICE` +
  /// `FOREGROUND_SERVICE_LOCATION`** (este último desde Android 14), y en iPhone
  /// `NSLocationAlwaysAndWhenInUseUsageDescription` + `UIBackgroundModes → location`.
  ///
  /// 🔴 **El SDK no declara ninguno de esos y no los va a declarar.** Los declara la
  /// aplicación anfitriona. Si no están, este modo **se apaga solo y lo dice** — ver
  /// `Ubicacion.arrancarContinuo`. Ver también el README, sección «Ubicación continua».
  ///
  /// 🔴 **Y no llega a la aplicación MATADA.** Mientras la actividad viva —la persona
  /// apretó inicio, apagó la pantalla, está en otra aplicación— las lecturas siguen
  /// llegando por el servicio en primer plano de `geolocator`. Si la persona la barre de
  /// las recientes, o si el teléfono la mata, se cortan hasta que la vuelva a abrir.
  /// Sostener eso necesitaría un servicio propio con su propio isolate, y ese paquete le
  /// inyectaría permisos a TODA aplicación que instale el SDK — que es exactamente lo que
  /// este repositorio existe para no hacer.
  enSegundoPlano,
}

/// LOS TEXTOS DE LA SEGUNDA PREGUNTA — la de «siempre», que NO es la de «mientras usás la
/// aplicación».
///
/// ══ 🔴 POR QUÉ SON DOS PREGUNTAS Y NO UNA ══
///
/// Android las trata como dos permisos distintos y **prohíbe pedirlas juntas**: desde
/// Android 11 el diálogo de «permitir siempre» ni siquiera se muestra, el sistema abre la
/// pantalla de Ajustes y la persona tiene que elegirlo ahí a mano. Reusar el modal de
/// «mientras usás la aplicación» para esto sería pedirle que acepte de nuevo algo que ya
/// aceptó, y dejarla en una pantalla de Ajustes sin entender qué fue a buscar.
///
/// Y Google exige un texto casi literal antes de mostrar el diálogo. Los de fábrica de
/// abajo lo cumplen; el comercio los cambia desde su consola, y si escribe algo que no lo
/// cumpla, el rechazo se lo come él. Ver la ficha de `ACCESS_BACKGROUND_LOCATION` en
/// `catalogo_de_permisos.dart`.
class TextosDeSiempre {
  const TextosDeSiempre({
    this.titulo = 'Un paso más: siempre',
    this.cuerpo =
        'Esta aplicación recolecta datos de ubicación para saber cuánto te movés '
        'incluso cuando está cerrada o no la estás usando. En la pantalla que sigue, '
        'elegí «Permitir siempre».',
    this.aceptar = 'Permitir siempre',
    this.ahoraNo = 'Ahora no',
    this.motivos = const [
      'Es la zona, no la dirección exacta',
      'Vas a ver un aviso fijo mientras esté midiendo',
      'Lo cortás cuando quieras desde los ajustes',
    ],
    this.avisoTitulo = 'Midiendo tu zona',
    this.avisoCuerpo = 'Tocá para ver o cortar esto.',
  });

  final String titulo;
  final String cuerpo;
  final String aceptar;
  final String ahoraNo;
  final List<String> motivos;

  /// EL AVISO FIJO DE LA BARRA, que en Android **no es opcional**: un servicio que lee la
  /// ubicación con la aplicación en el fondo obliga a mostrar una notificación permanente.
  ///
  /// 🔴 Lo escribe el comercio porque lleva su marca y va a estar en la barra de estado de
  /// la persona todo el día. Un texto de relleno ahí es lo que hace que alguien entre a los
  /// ajustes a cortar el permiso.
  final String avisoTitulo;
  final String avisoCuerpo;

  factory TextosDeSiempre.fromJson(Map<String, dynamic>? j) {
    const d = TextosDeSiempre();
    if (j == null) return d;
    String t(String k, String x) {
      final v = j[k];
      return (v is String && v.trim().isNotEmpty) ? v.trim() : x;
    }
    final m = j['motivos'];
    return TextosDeSiempre(
      titulo: t('titulo', d.titulo),
      cuerpo: t('cuerpo', d.cuerpo),
      aceptar: t('aceptar', d.aceptar),
      ahoraNo: t('ahoraNo', d.ahoraNo),
      motivos: (m is List && m.isNotEmpty)
          ? m.map((e) => '$e').where((e) => e.trim().isNotEmpty).toList()
          : d.motivos,
      avisoTitulo: t('avisoTitulo', d.avisoTitulo),
      avisoCuerpo: t('avisoCuerpo', d.avisoCuerpo),
    );
  }
}

/// SI SE LE OFRECE LA UBICACIÓN, CUÁNDO, CÓMO SE LEE, Y CADA CUÁNTO SE REINSISTE.
///
/// Nace apagada. Un comercio que no la necesita no le muestra a su gente un diálogo
/// de más, y prender esto sin querer es pedir un permiso que no hace falta.
class PoliticaDeUbicacion {
  const PoliticaDeUbicacion({
    this.activa = false,
    this.momento = MomentoDeUbicacion.despuesDeEntrar,
    this.reintentarCadaDias = 14,
    this.textos = const TextosDeUbicacion(),
    this.modo = ModoDeLectura.alEntrar,
    this.cadaMinutosEnPrimerPlano = minutosEnPrimerPlanoPorOmision,
    this.cadaMinutosEnSegundoPlano = minutosEnSegundoPlanoPorOmision,
    this.textosDeSiempre = const TextosDeSiempre(),
  });

  final bool activa;
  final MomentoDeUbicacion momento;

  /// Cómo se lee. Por omisión, **lo de siempre**: una lectura al entrar.
  final ModoDeLectura modo;

  /// ══ CADA CUÁNTO, EN PRIMER PLANO — DOS MINUTOS ══
  ///
  /// La aplicación está abierta, así que no hay ni servicio en el fondo ni aviso fijo ni
  /// permiso nuevo: el costo es un despertar del proveedor fusionado cada dos minutos, sin
  /// GPS. En una sesión típica de tres minutos eso deja **una o dos** marcas en vez de las
  /// cero o una que deja el freno de dos horas — que es todo lo que este modo promete.
  ///
  /// Más rápido no compra nada: con `ACCESS_COARSE_LOCATION` Android redondea la respuesta
  /// a ~2 km, así que dos lecturas separadas por veinte segundos dan el mismo punto.
  final int cadaMinutosEnPrimerPlano;

  /// ══ 🔴 CADA CUÁNTO, EN SEGUNDO PLANO — TREINTA MINUTOS, Y ACÁ ESTÁ EL PORQUÉ ══
  ///
  /// Tres cosas ponen el número, y las tres tiran para el mismo lado:
  ///
  ///  1. **La batería.** Se lee con `LocationAccuracy.low`, que en Android es
  ///     `PRIORITY_LOW_POWER`: no enciende el GPS y se conforma con antenas y wifi. Lo que
  ///     cuesta no es el arreglo, es despertar el teléfono. Android limita por su cuenta a
  ///     **una lectura por hora** a las aplicaciones en el fondo que NO tienen servicio en
  ///     primer plano; treinta minutos es el doble de eso, que es lo máximo que se puede
  ///     defender como «conservador».
  ///
  ///  2. **🔴 EL TECHO DEL SERVICIO, que es el que de verdad manda.** El back guarda las
  ///     últimas **60** posiciones por aparato (`CUANTAS_SE_GUARDAN`). A 30 min son 48 al
  ///     día, así que esas 60 cubren **25 horas**: un día entero, que es justo la pregunta
  ///     («cuánto se mueve **en el día**»). A 15 min cubrirían 15 horas y el día dejaría de
  ///     entrar; a 5 min, cinco horas. **Los quince días que pidió Juan NO entran a ninguna
  ///     frecuencia** mientras el servicio guarde 60 y no agregue por día — con 60 huecos,
  ///     quince días salen a una lectura cada seis horas, que es el freno viejo que se acaba
  ///     de sacar por inútil. Eso se arregla del lado del servicio, no de acá.
  ///
  ///  3. **Que no se lo revoquen.** Mientras esto corre hay un aviso fijo en la barra de la
  ///     persona. Cuanto menos se note el teléfono caliente, más dura el permiso.
  ///
  /// Configurable por comercio, con piso de [minimoMinutosEnSegundoPlano]: por debajo de
  /// cinco minutos Android estrangula igual y el gasto de batería deja de ser defendible.
  final int cadaMinutosEnSegundoPlano;

  /// Los textos de la segunda pregunta y del aviso fijo. Ver [TextosDeSiempre].
  final TextosDeSiempre textosDeSiempre;

  /// Ver [cadaMinutosEnPrimerPlano].
  static const minutosEnPrimerPlanoPorOmision = 2;

  /// Ver [cadaMinutosEnSegundoPlano].
  static const minutosEnSegundoPlanoPorOmision = 30;

  /// Piso: por debajo de esto Android estrangula igual y el gasto no se justifica.
  static const minimoMinutosEnSegundoPlano = 5;

  /// Piso del primer plano. Un minuto ya es más rápido de lo que la precisión aproximada
  /// puede distinguir; menos es gastar batería para repetir el mismo punto.
  static const minimoMinutosEnPrimerPlano = 1;

  /// Cada cuánto se lee de verdad, para el modo que esté puesto. Ya viene acotado: un
  /// comercio que escriba `0` en la consola no puede dejar el teléfono leyendo sin parar.
  Duration get cada => switch (modo) {
        ModoDeLectura.alEntrar => Duration.zero,
        ModoDeLectura.enPrimerPlano => Duration(
            minutes: cadaMinutosEnPrimerPlano < minimoMinutosEnPrimerPlano
                ? minimoMinutosEnPrimerPlano
                : cadaMinutosEnPrimerPlano),
        ModoDeLectura.enSegundoPlano => Duration(
            minutes: cadaMinutosEnSegundoPlano < minimoMinutosEnSegundoPlano
                ? minimoMinutosEnSegundoPlano
                : cadaMinutosEnSegundoPlano),
      };

  /// Cada cuántos días volver a ofrecerla a quien cerró el modal sin aceptar.
  ///
  /// 🔴 Esto NO reintenta contra quien le dijo que no al diálogo del SISTEMA: ese «no»
  /// Android lo recuerda solo y ya no vuelve a mostrar nada. Reinsistir ahí sería
  /// levantar un modal que no lleva a ninguna parte. Sólo se le vuelve a ofrecer a
  /// quien todavía puede decir que sí.
  final int reintentarCadaDias;
  final TextosDeUbicacion textos;

  factory PoliticaDeUbicacion.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const PoliticaDeUbicacion();
    int entero(String clave, int siNo) =>
        (j[clave] is num) ? (j[clave] as num).toInt() : siNo;
    return PoliticaDeUbicacion(
      activa: j['activa'] == true,
      momento: j['momento'] == 'laAppDecide'
          ? MomentoDeUbicacion.laAppDecide
          : MomentoDeUbicacion.despuesDeEntrar,
      reintentarCadaDias: entero('reintentarCadaDias', 14),
      textos: TextosDeUbicacion.fromJson(
          j['textos'] is Map ? Map<String, dynamic>.from(j['textos'] as Map) : null),
      modo: modoDesde(j['modo'] as String?),
      cadaMinutosEnPrimerPlano:
          entero('cadaMinutosEnPrimerPlano', minutosEnPrimerPlanoPorOmision),
      cadaMinutosEnSegundoPlano:
          entero('cadaMinutosEnSegundoPlano', minutosEnSegundoPlanoPorOmision),
      textosDeSiempre: TextosDeSiempre.fromJson(j['textosDeSiempre'] is Map
          ? Map<String, dynamic>.from(j['textosDeSiempre'] as Map)
          : null),
    );
  }

  /// 🔴 UNA PALABRA QUE NO SE CONOCE CAE EN [ModoDeLectura.alEntrar], NUNCA HACIA ARRIBA.
  ///
  /// Es la misma regla que ya usa `PoliticaDeNotificaciones._momentoDesde`, y acá pesa más:
  /// si mañana el servicio inventa un modo nuevo, una aplicación vieja que no lo entiende
  /// tiene que seguir haciendo lo de siempre. Caer hacia el modo más caro sería prender un
  /// servicio en el fondo por una palabra mal escrita.
  static ModoDeLectura modoDesde(String? v) => switch (v) {
        'enPrimerPlano' => ModoDeLectura.enPrimerPlano,
        'enSegundoPlano' => ModoDeLectura.enSegundoPlano,
        _ => ModoDeLectura.alEntrar,
      };
}

enum MomentoDeUbicacion {
  /// Al iniciar sesión, DESPUÉS de que se resolvió el permiso de notificaciones.
  ///
  /// 🔴 Nunca los dos diálogos juntos: dos permisos seguidos apenas se abre la
  /// aplicación es la forma más rápida de que la persona diga que no a los dos, y el
  /// de notificaciones es el que el producto necesita.
  despuesDeEntrar,

  /// La aplicación decide cuándo, llamando a `AkPush.ofrecerUbicacion(context)`.
  /// Para quien quiera pedirla recién cuando sirve para algo — al abrir el mapa de
  /// sucursales, por ejemplo, que es cuando más gente acepta.
  laAppDecide,
}
