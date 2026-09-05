/// EL CATÁLOGO DE PERMISOS — la única fuente de verdad de lo que este SDK puede llegar
/// a aportarle al manifiesto de una aplicación anfitriona, y de qué hace falta para que
/// una tienda lo apruebe.
///
/// 🔴 NO ES UNA LISTA BLANCA NI UNA LISTA NEGRA. Es un registro con justificación, donde
/// cada permiso dice **para qué rubro está libre, condicionado o prohibido**, y qué hay
/// que hacer concretamente cuando está condicionado.
///
/// La diferencia con una lista plana importa, y costó una corrección: `READ_MEDIA_IMAGES`
/// está vetado para una aplicación de préstamo personal, pero para una aseguradora que
/// necesita la foto de un siniestro está condicionado, que es otra cosa. Ver `rubros.dart`.
///
/// **Una ficha alimenta cinco cosas**, que antes se escribían por separado y se
/// contradecían entre sí:
///
///   1. la comprobación que falla si aparece un permiso sin declarar (`bin/muro.dart`)
///   2. el manual que lee el integrador
///   3. la declaración de Data Safety de Google Play
///   4. el manifiesto de privacidad de Apple
///   5. el texto que ve la persona cuando se le pide
///
/// 🔴 EL MOTIVO REAL, medido el 2026-08-31 sobre CredoLab en una app de producción: sus
/// paquetes declaran READ_CONTACTS, READ_CALENDAR, GET_ACCOUNTS y READ_PHONE_STATE en
/// sus propios manifiestos, y el fusionador se los inyecta a TODA aplicación que los
/// instale — la use o no. La ficha de Play de esa app asusta por datos que nunca va a
/// obtener. Este archivo existe para que no nos pase, y `bin/muro.dart` para que no
/// dependa de que alguien se acuerde.
library;

import 'rubros.dart';

export 'rubros.dart';

/// En qué sistema aplica un permiso. La distinción no es cosmética: hay permisos que en
/// iOS ni siquiera existen como concepto, y decir «ambas» cuando no es cierto hace que
/// el manual mienta.
enum Plataforma { android, ios, ambas }

/// Cuánta fricción le pone a la gente del comercio, no cuánto cuesta programarlo.
enum Nivel {
  /// No se le muestra ningún diálogo a nadie. Se tiene en el 100% de las instalaciones.
  ninguno,

  /// Un diálogo común, que la mayoría acepta.
  comun,

  /// Aparece destacado en la ficha de la tienda y baja las instalaciones.
  asusta,

  /// Google o Apple lo revisan a mano y hay que justificarlo con un formulario.
  revisionManual,
}

/// Por qué es lícito recolectar este dato. No es un adorno legal: decide qué pasa cuando
/// alguien revoca. Con `consentimiento`, revocar obliga a dejar de recolectar Y a borrar
/// lo recolectado. Con `contrato`, el dato hace falta para prestar el servicio.
enum BaseLegal { consentimiento, contrato }

/// Cuánto tiempo se guarda lo que se recolecta con este permiso.
///
/// 🔴 VA EN LA FICHA DEL PERMISO Y NO EN UNA POLÍTICA APARTE, porque una política de
/// retención que vive lejos del dato se desactualiza y nadie se entera.
class Retencion {
  final String enPalabras;
  final int? dias;
  const Retencion(this.enPalabras, {this.dias});
  static const mientrasExista = Retencion('mientras el aparato siga dado de alta');
  static const noSeGuarda = Retencion('no se guarda: el módulo no está construido');
}

/// La ficha de un permiso.
class PermisoDeclarado {
  /// El nombre exacto como aparece en el manifiesto. Es la clave contra la que compara
  /// el muro, así que un error de tipeo acá hace fallar la comprobación — que es
  /// preferible a que la deje pasar.
  final String nombre;

  final Plataforma plataforma;

  /// 🔴 QUÉ MÓDULO LO NECESITA. Sin módulo no entra: un permiso que no le sirve a ningún
  /// módulo es uno que alguien arrastró sin querer, que es el caso de CredoLab.
  final String modulo;

  /// Para qué sirve, en una frase y en castellano. Se muestra tal cual en el manual y
  /// alimenta el modal, así que se escribe para quien lo lee en el teléfono.
  final String paraQue;

  final Nivel nivel;

  /// Quién lo mete en el manifiesto: una dependencia nuestra, o la propia aplicación.
  /// Decide de quién es la responsabilidad cuando aparece algo raro.
  final String loAporta;

  /// Para qué rubros está libre, condicionado o prohibido.
  final Disponibilidad disponibilidad;

  /// 🔴 QUÉ HAY QUE HACER para que te lo aprueben. Vacío si no hace falta nada.
  final List<Requisito> requisitos;

  /// Qué categorías sensibles toca. Si toca alguna, queda prohibido mientras la puerta
  /// del sistema esté cerrada, sin importar el rubro.
  final List<DatoSensible> toca;

  /// La casilla exacta del formulario de Data Safety de Google Play, con las palabras
  /// del formulario y no con las nuestras: quien lo llena tiene que poder buscarla.
  final String dataSafety;

  /// Qué se declara en el manifiesto de privacidad de Apple. `null` si no aplica.
  final String? manifiestoApple;

  /// La cadena de propósito de iOS, cuando existe.
  final String? razonApple;

  final Retencion retencion;
  final BaseLegal base;

  const PermisoDeclarado({
    required this.nombre,
    required this.plataforma,
    required this.modulo,
    required this.paraQue,
    required this.nivel,
    required this.loAporta,
    required this.disponibilidad,
    required this.dataSafety,
    required this.retencion,
    required this.base,
    this.requisitos = const [],
    this.toca = const [],
    this.manifiestoApple,
    this.razonApple,
  });

  /// ¿Lo aporta el paquete, o lo declara la aplicación anfitriona?
  bool get esNuestro => loAporta != 'la aplicación anfitriona';

  /// 🔴 EL VEREDICTO FINAL para un rubro, ya con la puerta de dato sensible aplicada.
  /// Es lo único que debería consultar el muro: encadena las dos reglas en el orden
  /// correcto, y así no puede haber un lugar que consulte una y se olvide de la otra.
  Estado estadoPara(Rubro rubro) =>
      conLaPuertaCerrada(disponibilidad.para(rubro), toca);

  /// Por qué quedó en ese estado, para el mensaje del muro.
  String porQuePara(Rubro rubro) {
    if (toca.isNotEmpty && !sistemaAdmiteDatoSensible) return motivoPuertaCerrada;
    return disponibilidad.porQue;
  }
}

// ═════════════════════════════════════════════════════════════════════════════════════
// EL CATÁLOGO
// ═════════════════════════════════════════════════════════════════════════════════════
//
// Medido el 2026-08-31 sobre la app de demostración en release: una aplicación que
// instala este SDK termina con siete permisos, y **sólo dos los declara ella**. Los otros
// cinco los aportan las dependencias, y ninguno es peligroso ni aparece destacado en la
// ficha de Play. No es casualidad: es la razón por la que se eligieron esas dependencias.
//
// Los de más abajo —fotos, cámara, contactos, ubicación exacta— NO se usan hoy. Están
// declarados con su procedimiento real de aprobación para que el día que un comercio los
// necesite, la respuesta sea una lista de tareas y no una investigación de dos días.

// `final` y no `const`: los ayudantes `libreParaTodos` y `condicionadoSalvo` son
// métodos, y Dart no los admite dentro de una expresión constante. Se inicializa una
// sola vez al arrancar y no cambia nunca, que es lo que hacía falta.
final List<PermisoDeclarado> catalogoDePermisos = [
  // ═══ LO QUE HOY APORTAN LAS DEPENDENCIAS ═════════════════════════════════════════

  PermisoDeclarado(
    nombre: 'android.permission.INTERNET',
    plataforma: Plataforma.android,
    modulo: 'avisos',
    paraQue: 'Hablar con el servicio. Sin esto no llega ningún aviso.',
    nivel: Nivel.ninguno,
    loAporta: 'firebase_messaging',
    disponibilidad: Disponibilidad.libreParaTodos(
        'No accede a ningún dato del usuario. Ninguna tienda lo trata como sensible.'),
    dataSafety: 'no se declara: no es acceso a datos del usuario',
    retencion: Retencion.mientrasExista,
    base: BaseLegal.contrato,
  ),
  PermisoDeclarado(
    nombre: 'android.permission.ACCESS_NETWORK_STATE',
    plataforma: Plataforma.android,
    modulo: 'avisos',
    paraQue:
        'Saber si hay conexión, para no reintentar un envío contra un teléfono sin red.',
    nivel: Nivel.ninguno,
    loAporta: 'firebase_messaging',
    disponibilidad: Disponibilidad.libreParaTodos('No identifica a nadie.'),
    dataSafety: 'no se declara: no identifica a nadie',
    retencion: Retencion.mientrasExista,
    base: BaseLegal.contrato,
  ),
  PermisoDeclarado(
    nombre: 'android.permission.WAKE_LOCK',
    plataforma: Plataforma.android,
    modulo: 'avisos',
    paraQue:
        'Despertar el teléfono lo justo para mostrar un aviso que llegó con la pantalla apagada.',
    nivel: Nivel.ninguno,
    loAporta: 'firebase_messaging',
    disponibilidad: Disponibilidad.libreParaTodos('No accede a ningún dato.'),
    dataSafety: 'no se declara',
    retencion: Retencion.mientrasExista,
    base: BaseLegal.contrato,
  ),
  PermisoDeclarado(
    nombre: 'android.permission.VIBRATE',
    plataforma: Plataforma.android,
    modulo: 'avisos',
    paraQue: 'Vibrar al mostrar un aviso, si el canal lo tiene configurado.',
    nivel: Nivel.ninguno,
    loAporta: 'flutter_local_notifications',
    disponibilidad: Disponibilidad.libreParaTodos('No accede a ningún dato.'),
    dataSafety: 'no se declara',
    retencion: Retencion.mientrasExista,
    base: BaseLegal.contrato,
  ),
  PermisoDeclarado(
    nombre: 'com.google.android.c2dm.permission.RECEIVE',
    plataforma: Plataforma.android,
    modulo: 'avisos',
    paraQue: 'Recibir el aviso que manda Google. Es el canal por donde llega el push.',
    nivel: Nivel.ninguno,
    loAporta: 'firebase_messaging',
    // No es un permiso del sistema: lo define Google y sólo sirve para que otra
    // aplicación no pueda hacerse pasar por el repartidor de avisos.
    disponibilidad: Disponibilidad.libreParaTodos(
        'Lo define Google para su propio canal. No se le muestra a nadie.'),
    dataSafety: 'no se declara: no es acceso a datos del usuario',
    retencion: Retencion.mientrasExista,
    base: BaseLegal.contrato,
  ),

  // ═══ LO QUE DECLARA LA APLICACIÓN ANFITRIONA ═════════════════════════════════════
  //
  // 🔴 Estos NO los aporta el paquete, y es deliberado. Un permiso declarado por una
  // dependencia se le aparece en la ficha de Play a toda aplicación que la instale, la
  // use o no. Declararlos del lado de la aplicación deja la decisión donde corresponde.

  PermisoDeclarado(
    nombre: 'android.permission.POST_NOTIFICATIONS',
    plataforma: Plataforma.android,
    modulo: 'avisos',
    paraQue: 'Mostrarte avisos. Android 13 en adelante lo pide explícitamente.',
    nivel: Nivel.comun,
    loAporta: 'la aplicación anfitriona',
    disponibilidad: Disponibilidad.libreParaTodos(
        'Sin restricción por rubro. Es un permiso común desde Android 13 y no tiene '
        'formulario de declaración especial.'),
    dataSafety: 'no se declara como dato; el token sí, como «Device or other IDs»',
    razonApple: 'ninguna: el diálogo de iOS usa el texto de Apple y no se personaliza',
    retencion: Retencion('mientras la dirección del teléfono siga sirviendo'),
    base: BaseLegal.consentimiento,
  ),
  PermisoDeclarado(
    nombre: 'android.permission.ACCESS_COARSE_LOCATION',
    plataforma: Plataforma.ambas,
    modulo: 'ubicacion',
    paraQue: 'Saber tu zona —no tu dirección— mientras usás la aplicación.',
    nivel: Nivel.comun,
    loAporta: 'la aplicación anfitriona',
    // 🔴 NO está en la lista vetada de la política de préstamos personales; el que sí
    // está es FINE. Se eligió COARSE porque asusta menos, y resultó ser además lo único
    // que deja al SDK del lado correcto de esa política.
    disponibilidad: Disponibilidad.libreParaTodos(
        'La política de préstamos personales veta ACCESS_FINE_LOCATION, no COARSE. '
        'Ningún rubro lo tiene prohibido.'),
    requisitos: [
      Requisito(
        'Nunca pedirlo sólo para publicidad o analítica: Google lo prohíbe expresamente.',
        fuente: 'support.google.com/googleplay/android-developer/answer/9799150',
      ),
    ],
    dataSafety: 'Location → Approximate location',
    manifiestoApple: 'NSPrivacyCollectedDataTypes → Location (sin la marca de precisa)',
    razonApple: 'NSLocationWhenInUseUsageDescription',
    retencion: Retencion('las últimas 5 lecturas por aparato, y 90 días', dias: 90),
    base: BaseLegal.consentimiento,
  ),

  // ═══ LOS QUE TODAVÍA NO SE USAN, CON SU PROCEDIMIENTO REAL ═══════════════════════
  //
  // Ninguno lo pide el SDK hoy. Están acá porque el día que un comercio los necesite, la
  // respuesta tiene que ser una lista de tareas. Los requisitos salen del levantamiento
  // del 2026-08-31, cada uno con su fuente para poder volver a comprobarlo: las políticas
  // de las tiendas cambian, y un requisito citado de memoria es peligroso.

  PermisoDeclarado(
    nombre: 'android.permission.ACCESS_FINE_LOCATION',
    plataforma: Plataforma.ambas,
    modulo: 'ubicacion',
    paraQue: 'Saber tu posición exacta, no sólo la zona.',
    nivel: Nivel.asusta,
    loAporta: 'la aplicación anfitriona',
    disponibilidad: Disponibilidad.condicionadoSalvo(
      [Rubro.prestamoPersonal],
      porQue: 'Está en la lista explícita de permisos vetados de la política de '
          'préstamos personales de Google Play. Para el resto de los rubros se puede, si '
          'hay un beneficio significativo para la persona.',
    ),
    requisitos: [
      Requisito(
        'Justificar un beneficio significativo: seguridad física, seguridad percibida o '
        'salud. Nunca pedirlo sólo para publicidad o analítica.',
        fuente: 'support.google.com/googleplay/android-developer/answer/9799150',
      ),
      Requisito(
        'Considerar antes el «botón de ubicación» de Android, que no pide permiso.',
        fuente:
            'developer.android.com/guide/topics/permissions/private-alternatives/location-button',
      ),
    ],
    dataSafety: 'Location → Precise location',
    manifiestoApple: 'NSPrivacyCollectedDataTypes → Location (precisa)',
    razonApple: 'NSLocationWhenInUseUsageDescription',
    retencion: Retencion.noSeGuarda,
    base: BaseLegal.consentimiento,
  ),

  // 🔴 QUEDA EN EL MÓDULO «rastreo» A PROPÓSITO, aunque desde el 2026-09-05 quien lo usa es
  // `ubicacion` en modo `enSegundoPlano`. Moverlo lo cambiaría de grupo en la consola del
  // comercio, y ese agrupamiento lo sirve el back: es un cambio de los dos lados, no de éste.
  // Lo que sí importa que se lea acá está en los requisitos.
  PermisoDeclarado(
    nombre: 'android.permission.ACCESS_BACKGROUND_LOCATION',
    plataforma: Plataforma.ambas,
    modulo: 'rastreo',
    paraQue: 'Seguir tu ubicación con la aplicación cerrada.',
    nivel: Nivel.revisionManual,
    loAporta: 'la aplicación anfitriona',
    disponibilidad: Disponibilidad.condicionadoSalvo(
      [Rubro.prestamoPersonal],
      porQue: 'El trámite más exigente de Android. Google acepta UNA sola función que lo '
          'justifique; transporte y reparto son los rubros donde más se aprueba.',
    ),
    requisitos: [
      Requisito(
        'Mostrar una pantalla propia antes del diálogo del sistema, con un texto casi '
        'literal: «[La app] recolecta datos de ubicación para habilitar [función] '
        'incluso cuando la aplicación está cerrada o no se está usando».',
        fuente: 'support.google.com/googleplay/android-developer/answer/11150561',
      ),
      Requisito(
        'Llenar el Formulario de Declaración de Permisos en Play Console explicando por '
        'qué UNA sola función no puede andar sin ubicación en segundo plano.',
        fuente: 'support.google.com/googleplay/android-developer/answer/9214102',
      ),
      Requisito(
        'Mandar un video de 30 segundos o menos que muestre la función activándose en '
        'segundo plano, la pantalla de aviso propia y el diálogo del sistema.',
        fuente: 'support.google.com/googleplay/android-developer/answer/9214102',
      ),
      Requisito(
        'En iOS: pedir primero «mientras se usa» y sólo después «siempre». No se puede '
        'pedir «siempre» de entrada.',
        fuente: 'developer.apple.com/app-store/review/guidelines/ · 5.1.5',
      ),
      Requisito(
        '🔴 No viene solo: hay que declarar además FOREGROUND_SERVICE y —si la aplicación '
        'apunta a Android 14— FOREGROUND_SERVICE_LOCATION. Sin el segundo, el sistema tumba '
        'la aplicación al arrancar el servicio. Los dos tienen ficha propia en este catálogo.',
        fuente: 'developer.android.com/about/versions/14/changes/fgs-types-required',
      ),
      Requisito(
        'Lo declara la APLICACIÓN, nunca hz_collection_sdk. El SDK lo detecta en tiempo de '
        'ejecución y apaga el modo de segundo plano si falta, en vez de medir nada en '
        'silencio. Ver Ubicacion.sePuedeEnSegundoPlano y el README.',
        fuente: 'android/src/main/AndroidManifest.xml de este paquete',
      ),
    ],
    dataSafety: 'Location → Precise location (en segundo plano)',
    manifiestoApple: 'NSPrivacyCollectedDataTypes → Location',
    razonApple: 'NSLocationAlwaysAndWhenInUseUsageDescription',
    retencion: Retencion.noSeGuarda,
    base: BaseLegal.consentimiento,
  ),

  // ── LOS DOS QUE VIAJAN CON EL SEGUNDO PLANO Y QUE NADIE ESPERA ──────────────────
  //
  // 🔴 SE AGREGAN EL 2026-09-05, Y NO POR PROLIJIDAD. Sin ficha, el muro los marca «sin
  // ficha en el catálogo» y **falla** en la aplicación del comercio que siguió al pie de la
  // letra lo que dice el README sobre la ubicación en segundo plano. Un muro que da rojo por
  // seguir la documentación propia se apaga, y con él se apaga la comprobación que de verdad
  // importa.
  //
  // No los pide el SDK: los necesita `geolocator` para sostener las lecturas con la
  // aplicación en el fondo, y su manifiesto declara el SERVICIO pero no los PERMISOS.

  PermisoDeclarado(
    nombre: 'android.permission.FOREGROUND_SERVICE',
    plataforma: Plataforma.android,
    modulo: 'ubicacion',
    paraQue:
        'Sostener la lectura de ubicación con la aplicación en el fondo, con un aviso fijo.',
    nivel: Nivel.ninguno,
    loAporta: 'la aplicación anfitriona',
    disponibilidad: Disponibilidad.libreParaTodos(
        'No accede a ningún dato por sí mismo: sólo permite que un servicio siga corriendo '
        'con la aplicación en el fondo, y obliga a mostrar un aviso permanente. Quien decide '
        'el veredicto es el permiso de ubicación que lo acompaña, no éste.'),
    requisitos: [
      Requisito(
        'Sólo tiene sentido junto a ACCESS_BACKGROUND_LOCATION. Declararlo solo no habilita '
        'nada y agrega un renglón a la ficha de la tienda sin motivo.',
        fuente: 'developer.android.com/develop/background-work/services/fgs',
      ),
    ],
    dataSafety: 'no se declara: no es un dato',
    retencion: Retencion.mientrasExista,
    base: BaseLegal.consentimiento,
  ),

  PermisoDeclarado(
    nombre: 'android.permission.FOREGROUND_SERVICE_LOCATION',
    plataforma: Plataforma.android,
    modulo: 'ubicacion',
    paraQue:
        'Declarar que el servicio en primer plano es de ubicación, obligatorio en Android 14.',
    nivel: Nivel.ninguno,
    loAporta: 'la aplicación anfitriona',
    disponibilidad: Disponibilidad.libreParaTodos(
        'No accede a ningún dato: es la etiqueta de tipo del servicio. El veredicto lo pone '
        'ACCESS_BACKGROUND_LOCATION, que es el que Google revisa a mano.'),
    requisitos: [
      Requisito(
        '🔴 Obligatorio si la aplicación apunta a Android 14 (API 34) o más. Sin él, el '
        'sistema TUMBA la aplicación al arrancar el servicio de ubicación — no la degrada, '
        'la mata, con una SecurityException.',
        fuente: 'developer.android.com/about/versions/14/changes/fgs-types-required',
      ),
      Requisito(
        'Además del permiso, el <service> tiene que llevar foregroundServiceType="location". '
        'El manifiesto de geolocator ya lo declara; el permiso NO, y por eso va acá.',
        fuente: 'developer.android.com/about/versions/14/changes/fgs-types-required',
      ),
    ],
    dataSafety: 'no se declara: no es un dato',
    retencion: Retencion.mientrasExista,
    base: BaseLegal.consentimiento,
  ),

  PermisoDeclarado(
    nombre: 'android.permission.READ_MEDIA_IMAGES',
    plataforma: Plataforma.ambas,
    modulo: 'medios',
    paraQue: 'Leer tus fotos, cuando el selector del sistema no alcanza.',
    nivel: Nivel.revisionManual,
    loAporta: 'la aplicación anfitriona',
    disponibilidad: Disponibilidad.condicionadoSalvo(
      [Rubro.prestamoPersonal],
      porQue: 'Vetado para préstamo personal y adelanto de sueldo. Para el resto se '
          'puede, pero sólo si el selector de fotos del sistema no alcanza para la '
          'función central — y tener un selector propio NO exime de declararlo.',
    ),
    requisitos: [
      Requisito(
        'Demostrar que el selector de fotos de Android no alcanza para la función '
        'central. Es el primer filtro y el que más rechaza.',
        fuente: 'support.google.com/googleplay/android-developer/answer/14115180',
      ),
      Requisito(
        'Llenar el Formulario de Declaración de Permisos en Play Console.',
        fuente: 'support.google.com/googleplay/android-developer/answer/9214102',
      ),
      Requisito(
        'Mandar un video de demostración de la función central.',
        fuente: 'support.google.com/googleplay/android-developer/answer/9214102',
      ),
      Requisito(
        'Mostrar una pantalla de aviso antes del diálogo, en lenguaje que entienda '
        'alguien de trece años, con opción real de rechazar.',
        fuente: 'support.google.com/googleplay/android-developer/answer/11150561',
      ),
      Requisito(
        'Contar con varias semanas de revisión. No hay apelación documentada.',
        fuente: 'support.google.com/googleplay/android-developer/answer/9214102',
      ),
      Requisito(
        'En iOS, Apple prefiere el selector fuera de proceso antes que el acceso completo.',
        fuente: 'developer.apple.com/app-store/review/guidelines/ · 5.1.1 (iii)',
      ),
    ],
    dataSafety: 'Photos and videos → Photos',
    manifiestoApple: 'NSPrivacyCollectedDataTypes → Photos or Videos',
    razonApple: 'NSPhotoLibraryUsageDescription',
    retencion: Retencion.noSeGuarda,
    base: BaseLegal.consentimiento,
  ),

  PermisoDeclarado(
    nombre: 'android.permission.CAMERA',
    plataforma: Plataforma.ambas,
    modulo: 'medios',
    paraQue: 'Usar la cámara, por ejemplo para una foto de verificación de identidad.',
    nivel: Nivel.asusta,
    loAporta: 'la aplicación anfitriona',
    disponibilidad: Disponibilidad.condicionadoSalvo(
      [Rubro.prestamoPersonal],
      porQue: 'No tiene formulario propio ni video: alcanza con el aviso previo y el '
          'permiso en tiempo de ejecución. Es de los usos mejor aceptados en banca.',
    ),
    requisitos: [
      Requisito(
        'Mostrar una pantalla de aviso antes del diálogo del sistema.',
        fuente: 'support.google.com/googleplay/android-developer/answer/11150561',
      ),
      Requisito(
        'En iOS, dar una indicación visible o audible mientras se graba.',
        fuente: 'developer.apple.com/app-store/review/guidelines/ · 2.5.14',
      ),
    ],
    dataSafety: 'Photos and videos',
    manifiestoApple: 'NSPrivacyCollectedDataTypes → Photos or Videos',
    razonApple: 'NSCameraUsageDescription',
    retencion: Retencion.noSeGuarda,
    base: BaseLegal.consentimiento,
  ),

  PermisoDeclarado(
    nombre: 'android.permission.READ_CONTACTS',
    plataforma: Plataforma.ambas,
    modulo: 'agenda',
    paraQue: 'Leer tu agenda de contactos.',
    nivel: Nivel.revisionManual,
    loAporta: 'la aplicación anfitriona',
    disponibilidad: Disponibilidad.condicionadoSalvo(
      [Rubro.prestamoPersonal],
      porQue: 'Vetado para préstamo personal y prohibido por ley en India desde 2022. '
          'Para otros rubros hay una lista cerrada de casos de uso válidos, y ninguno es '
          '«armar un puntaje»: se está cerrando, no abriendo.',
    ),
    requisitos: [
      Requisito(
        '🔴 Google va a exigir el selector de contactos del sistema: la declaración '
        'aparece en Play Console en septiembre de 2026 y es obligatoria en enero de 2027 '
        'para quien apunte a Android 17. Planificar contra esa fecha.',
        fuente: 'support.google.com/googleplay/android-developer/answer/16935362',
      ),
      Requisito(
        'Encajar en uno de los casos de uso cerrados: gestión de contactos, marcador, '
        'historial de llamadas, CRM, filtro de llamadas, accesibilidad, asistente '
        'personal, búsqueda de amigos, respaldo, autocompletado.',
        fuente: 'support.google.com/googleplay/android-developer/answer/16935362',
      ),
      Requisito(
        'En iOS, Apple lo prohíbe expresamente para armar una base de contactos propia o '
        'para vender a terceros.',
        fuente: 'developer.apple.com/app-store/review/guidelines/ · 5.1.2 (iv)',
      ),
    ],
    dataSafety: 'Contacts',
    manifiestoApple: 'NSPrivacyCollectedDataTypes → Contacts',
    razonApple: 'NSContactsUsageDescription',
    retencion: Retencion.noSeGuarda,
    base: BaseLegal.consentimiento,
  ),

  PermisoDeclarado(
    nombre: 'android.permission.QUERY_ALL_PACKAGES',
    plataforma: Plataforma.android,
    modulo: 'inventario',
    paraQue: 'Ver todas las aplicaciones instaladas en el teléfono.',
    nivel: Nivel.revisionManual,
    loAporta: 'la aplicación anfitriona',
    disponibilidad: Disponibilidad(
      porOmision: Estado.prohibido,
      porQue: 'Google sólo lo admite si inventariar aplicaciones es el propósito CENTRAL '
          'de la app —antivirus, lanzador, gestor de archivos, navegador—. Un SDK de '
          'datos no califica, y usarlo para analítica o para vender el dato es un uso '
          'inválido declarado. En iOS no hay equivalente y Apple lo trata como '
          'prohibido, no como trámite.',
      excepciones: {Rubro.banca: Estado.condicionado},
    ),
    requisitos: [
      Requisito(
        'Sólo en banca y billeteras, y sólo por seguridad de pagos. Hay que llenar el '
        'Formulario justificando que la función central queda inutilizable sin esto.',
        fuente: 'support.google.com/googleplay/android-developer/answer/10158779',
      ),
      Requisito(
        'La alternativa que sí se acepta: declarar un conjunto acotado de aplicaciones '
        'en <queries>, en vez del permiso amplio.',
        fuente: 'developer.android.com/training/package-visibility',
      ),
    ],
    dataSafety: 'App activity → Installed apps',
    retencion: Retencion.noSeGuarda,
    base: BaseLegal.consentimiento,
  ),

  PermisoDeclarado(
    nombre: 'com.google.android.gms.permission.AD_ID',
    plataforma: Plataforma.android,
    modulo: 'identificadores',
    paraQue: 'Leer el identificador de publicidad del teléfono.',
    nivel: Nivel.comun,
    loAporta: 'la aplicación anfitriona',
    disponibilidad: Disponibilidad(
      porOmision: Estado.condicionado,
      porQue: 'Sin veto por rubro comercial, pero prohibido en aplicaciones dirigidas '
          'exclusivamente a menores. Desde Android 13 hay que declararlo aunque la '
          'persona no haya limitado el rastreo.',
    ),
    requisitos: [
      Requisito(
        'Declarar el propósito en Play Console, en Contenido de la app → Advertising ID.',
        fuente: 'support.google.com/googleplay/android-developer/answer/6048248',
      ),
      Requisito(
        'En iOS equivale al IDFA, que exige el diálogo de App Tracking Transparency y '
        'declarar los dominios de rastreo en el manifiesto de privacidad.',
        fuente: 'developer.apple.com/app-store/review/guidelines/ · 5.1.2 (i)',
      ),
    ],
    dataSafety: 'sección propia: Advertising ID',
    manifiestoApple: 'NSPrivacyTracking = true + NSPrivacyTrackingDomains',
    razonApple: 'NSUserTrackingUsageDescription',
    retencion: Retencion.noSeGuarda,
    base: BaseLegal.consentimiento,
  ),

  // ═══ LO QUE TOCA DATO SENSIBLE — HOY CERRADO POR DECISIÓN PROPIA ═════════════════

  PermisoDeclarado(
    nombre: 'android.permission.BODY_SENSORS',
    plataforma: Plataforma.ambas,
    modulo: 'salud',
    paraQue: 'Leer sensores del cuerpo, como el ritmo cardíaco.',
    nivel: Nivel.revisionManual,
    loAporta: 'la aplicación anfitriona',
    // 🔴 LA PROHIBICIÓN MÁS DURA DEL LEVANTAMIENTO, y va contra el NEGOCIO, no contra el
    // código: Google prohíbe usar datos de salud para calificar crédito, elegibilidad de
    // seguro o aptitud laboral. Los tres, sin excepción.
    //
    // Apple SÍ tiene una excepción —la aseguradora puede, con su propia app— pero exige
    // que el dato NO se comparta con un tercero, y en el modelo de licenciar un SDK
    // nosotros SOMOS el tercero. La excepción existe y no nos alcanza. No es algo que se
    // arregle programando distinto.
    disponibilidad: Disponibilidad(
      porOmision: Estado.prohibido,
      porQue: 'Google prohíbe expresamente usar datos de salud para calificar crédito, '
          'elegibilidad de seguro o aptitud laboral. Apple admite una excepción para la '
          'propia aseguradora, pero exige no compartir el dato con un tercero — y un SDK '
          'licenciado es un tercero.',
    ),
    toca: [DatoSensible.salud],
    requisitos: [
      Requisito(
        'Llenar la declaración de aplicaciones de salud en Play Console. Es obligatoria '
        'para toda app publicada, aunque no toque salud (hay opción «ninguna»).',
        fuente: 'support.google.com/googleplay/android-developer/answer/14738291',
      ),
    ],
    dataSafety: 'Health and fitness → Health info',
    manifiestoApple: 'NSPrivacyCollectedDataTypes → Health and Fitness',
    razonApple: 'NSHealthShareUsageDescription',
    retencion: Retencion.noSeGuarda,
    base: BaseLegal.consentimiento,
  ),
];

/// Los nombres, para comparar rápido. Lo usa el muro.
Set<String> get permisosDeclarados =>
    catalogoDePermisos.map((p) => p.nombre).toSet();

/// Busca la ficha de un permiso. `null` si no está declarado — y eso es justamente lo que
/// hace fallar al muro.
PermisoDeclarado? fichaDe(String nombre) {
  for (final p in catalogoDePermisos) {
    if (p.nombre == nombre) return p;
  }
  return null;
}

/// Los que no tienen ficha y sabemos por qué no la van a tener nunca.
///
/// 🔴 Son distintos de un permiso «prohibido para este rubro»: éstos no están en el
/// catálogo porque ningún módulo los va a necesitar en ningún rubro. La lista existe para
/// que el muro pueda dar un mensaje útil en vez de «permiso desconocido».
const Map<String, String> permisosProhibidos = {
  'android.permission.READ_SMS':
      'Restringido desde 2019 y reservado a la aplicación de mensajes por omisión. Y aun '
          'con la excepción bancaria, la política antispyware prohíbe sacar del teléfono '
          'el historial de mensajes no financieros para armar un puntaje.',
  'android.permission.RECEIVE_SMS':
      'Mismo caso que READ_SMS: restringido desde 2019 y reservado a la aplicación de '
          'mensajes por omisión. Si aparece, lo arrastró una dependencia — buscá cuál y '
          'sacala, porque le va a costar la publicación a quien instale el paquete.',
  'android.permission.READ_CALL_LOG':
      'Restringido a la aplicación de teléfono por omisión. En iOS no existe la API, así '
          'que además nunca sería una función pareja entre las dos plataformas.',
  'android.permission.READ_EXTERNAL_STORAGE':
      'En la lista explícita de permisos vetados de la política de préstamos personales, '
          'y para acceso a medios Google lo declara directamente un uso inválido: hay que '
          'usar el selector del sistema.',
  'android.permission.MANAGE_EXTERNAL_STORAGE':
      'Acceso a todo el almacenamiento. Es el que inyectaba permission_handler y por el '
          'que se lo sacó del paquete el 2026-08-30.',
  'android.permission.READ_PHONE_NUMBERS':
      'En la lista explícita de permisos vetados de la política de préstamos personales. '
          'En iOS no existe API pública para leer el número propio.',
  'android.permission.RECORD_AUDIO':
      'Ningún módulo del SDK lo necesita, así que si aparece lo trajo otra cosa. El '
          'micrófono en una aplicación financiera es de los permisos que más rechazo '
          'generan en la revisión y en la ficha de la tienda.',
  'android.permission.READ_CALENDAR':
      'Ningún módulo lo necesita. CredoLab lo usa para contar eventos; nosotros decidimos '
          'que el dato no vale la fricción que cuesta.',
  'android.permission.GET_ACCOUNTS':
      'Muy restringido desde Android 8 y prácticamente inútil hoy. CredoLab lo declara y '
          'lo único que obtiene es la cantidad de cuentas.',
  'android.permission.PACKAGE_USAGE_STATS':
      'Exige que la persona lo active a mano en Ajustes, sin diálogo del sistema. '
          'Fricción altísima para lo que da, y muy asociado a políticas de programas espía.',
};
