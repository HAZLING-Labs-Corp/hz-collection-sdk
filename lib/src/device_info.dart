import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Quién es este teléfono, y cómo se llama esta aplicación.
///
/// Dos usos distintos y conviene no confundirlos:
///
///  - El **identificador del paquete** es obligatorio: sin él el servidor no
///    puede verificar que la configuración que entrega sirve para esta
///    aplicación.
///  - Todo lo demás —modelo, marca, versión— es metadata y es **opcional**. Si
///    el canal nativo que la provee no responde, el alta sigue igual. Perder el
///    modelo del teléfono cuesta un dato de inventario; perder el alta cuesta
///    que esa persona no reciba nada.
class DatosDelDispositivo {
  const DatosDelDispositivo({
    required this.identificadorDePaquete,
    required this.plataforma,
    required this.desfaseUtcMinutos,
    this.deviceId,
    this.modelo,
    this.fabricante,
    this.marca,
    this.versionDelSistema,
    this.versionDeLaApp,
    this.esFisico,
    this.zonaHorariaAbreviada,
    this.idioma,
    this.nivelDeApi,
    this.anchoDePantalla,
    this.altoDePantalla,
    this.densidad,
    this.modoOscuro,
    this.textoAgrandado,
    this.idiomasPreferidos,
    this.reloj24Horas,
  });

  final String identificadorDePaquete;
  final String plataforma;
  final String? deviceId;
  final String? modelo;
  final String? fabricante;
  final String? marca;
  final String? versionDelSistema;
  final String? versionDeLaApp;
  final bool? esFisico;

  // ── Características del aparato que hacen falta para dibujar bien el aviso ──
  //
  // Todo lo que sigue lo entrega la propia plataforma de Flutter, sin canal
  // nativo y sin ningún diálogo. Es la misma telemetría que declaran los SDK de
  // push del mercado, y sirve para dos cosas concretas: decidir cómo se ve el
  // aviso en ESTE teléfono, y tener el inventario del parque.
  //
  // 🔴 Aunque no pida permiso, ES DATO RECOLECTADO: va declarado en el
  // formulario de seguridad de datos de Google Play y en las etiquetas de
  // privacidad de Apple. Publicar sin declararlo saca la aplicación de la
  // tienda, y eso no se descubre hasta el rechazo.

  /// Nivel de API de Android (34 = Android 14).
  ///
  /// Decide qué se puede hacer: el permiso de notificaciones sólo existe desde
  /// el 33, y por debajo se da por concedido. Sin este dato, «no dio permiso» y
  /// «su Android es viejo y no hay permiso que dar» se ven exactamente iguales
  /// en la consola, y son problemas distintos.
  final int? nivelDeApi;

  /// Pantalla en píxeles físicos y su densidad. Es lo que dice si la imagen que
  /// se manda con el aviso se va a ver bien o pixelada en este teléfono.
  final int? anchoDePantalla;
  final int? altoDePantalla;
  final double? densidad;

  /// Si el teléfono está en modo oscuro. Decide qué versión del ícono se ve: uno
  /// pensado para fondo claro desaparece en modo oscuro.
  final bool? modoOscuro;

  /// Si la persona agrandó el texto del sistema. Un título que entra en una
  /// línea a tamaño normal ocupa tres al 200%, y el aviso queda cortado.
  final bool? textoAgrandado;

  /// Todos los idiomas configurados, en orden. `idioma` es sólo el primero:
  /// alguien con el teléfono en inglés y español segundo entiende perfectamente
  /// un aviso en español, y con un solo idioma eso no se puede saber.
  final List<String>? idiomasPreferidos;

  /// Si usa reloj de 24 horas. Decide cómo se escribe una hora dentro del texto
  /// del aviso.
  final bool? reloj24Horas;

  // ── Cuándo y en qué idioma ──────────────────────────────────────────────
  //
  // El SDK no decide a qué hora sale un aviso —eso es del servidor—, pero es el
  // ÚNICO que puede saber en qué huso horario está el aparato: el servidor solo
  // ve una petición HTTP. Sin estos campos, «no enviar de madrugada» se calcula
  // contra la hora del servidor, y un aviso de cuota a las 3 de la mañana no se
  // lee: se desinstala la aplicación.
  //
  // 🔴 Son del APARATO, no de la persona. El idioma del teléfono es el que
  // eligió quien lo configuró, que no es necesariamente el que esa persona
  // quiere para SUS avisos —un teléfono en inglés en manos de alguien que lee
  // en español es lo más común del mundo—. Eso último es una PREFERENCIA, se
  // pregunta y se guarda contra la persona, no contra el dispositivo. Estos
  // campos sirven para adivinar bien cuando no hay preferencia, y nada más: en
  // cuanto exista una preferencia declarada, gana ella.

  /// Desfase respecto de UTC **en minutos**, con signo (Caracas: `-240`).
  ///
  /// Va siempre, porque siempre se puede calcular sin preguntarle nada a
  /// ninguna plataforma. Es el dato que de verdad permite decidir la hora de
  /// envío.
  ///
  /// Es el desfase **en el momento de recolectarlo**, no una regla: un país con
  /// horario de verano queda corrido una hora cuando cambia la estación, hasta
  /// el próximo arranque de la aplicación. Para programar con meses de
  /// anticipación en esos países haría falta el identificador IANA — ver
  /// [zonaHorariaAbreviada].
  final int desfaseUtcMinutos;

  /// Nombre corto del huso tal como lo da el sistema operativo (`VET`, `-04`,
  /// `GMT-04:00`).
  ///
  /// 🔴 **No es un identificador IANA** y el servidor no debe tratarlo como
  /// tal: no se puede pasar a una librería de husos horarios ni comparar con
  /// `America/Caracas`. Se llama «abreviada» justamente para que nadie lo
  /// confunda del otro lado.
  ///
  /// Dart no expone el identificador IANA por ningún camino, en ninguna
  /// plataforma: `DateTime.timeZoneName` devuelve lo que da la biblioteca de C
  /// del sistema, que es la abreviatura. Conseguir `America/Caracas` exige una
  /// dependencia nueva (`flutter_timezone`), y agregarla no estaba en el
  /// encargo. Mientras tanto viaja esto, que sirve para desempatar husos con el
  /// mismo desfase, más [desfaseUtcMinutos], que es lo que se usa para decidir.
  final String? zonaHorariaAbreviada;

  /// Idioma del aparato como etiqueta BCP-47 (`es-VE`, `pt-BR`).
  ///
  /// Es opcional porque puede no saberse todavía: el motor de Flutter contesta
  /// `und` mientras no le llegó el idioma del sistema.
  final String? idioma;

  /// Omite los nulos: un campo ausente y un campo con el texto "null" son cosas
  /// distintas para quien los lee del otro lado.
  Map<String, dynamic> toJson() => {
        // ── 🔴 DE QUÉ APLICACIÓN VIENE ESTE APARATO ──────────────────────────
        //
        // Los dos campos existían acá adentro desde siempre y NO viajaban. El
        // paquete se leía con `PackageInfo.fromPlatform()` y de ese par sólo se
        // mandaba la versión; el nombre viajaba en un único lugar —la consulta
        // de configuración, `?paquete=…`— para que el servidor verificara que
        // la configuración era de esta aplicación, y ahí moría.
        //
        // La consecuencia, medida el 2026-09-11 sobre cuatro comercios: de las
        // quince instalaciones guardadas, CERO sabían de qué aplicación venían.
        // Y un comercio puede tener varias: mundototal declara cinco.
        //
        // Sin esto, «¿de qué app vino esta persona?» no tiene respuesta, y dos
        // motores atados a dos aplicaciones distintas miran exactamente la
        // misma gente y devuelven el mismo número — mostrando dos resultados
        // que aparentan ser de cosas distintas. Eso es peor que no tener la
        // funcionalidad: es tenerla mintiendo.
        //
        // 🔴 EL PAQUETE VIAJA SÓLO SI SE SUPO. Sin canal nativo, `_leerPaquete`
        // devuelve cadena vacía a propósito —«no inventar un identificador que
        // no es el de esta aplicación»— y mandar esa cadena sería peor que no
        // mandar nada: del otro lado quedaría guardada como si fuera una app
        // llamada «», y ese aparato se atribuiría a ella. Ausente significa «no
        // se supo», que es la verdad.
        //
        // La plataforma sí va siempre: siempre se sabe.
        if (identificadorDePaquete.isNotEmpty)
          'packageName': identificadorDePaquete,
        'platform': plataforma,
        if (deviceId != null) 'deviceId': deviceId,
        if (modelo != null) 'model': modelo,
        if (fabricante != null) 'manufacturer': fabricante,
        if (marca != null) 'brand': marca,
        if (versionDelSistema != null) 'osVersion': versionDelSistema,
        if (versionDeLaApp != null) 'appVersion': versionDeLaApp,
        if (esFisico != null) 'isPhysicalDevice': esFisico,
        // Sin `if`: este siempre se pudo calcular, así que siempre viaja.
        'utcOffsetMinutes': desfaseUtcMinutos,
        if (zonaHorariaAbreviada != null)
          'timeZoneAbbreviation': zonaHorariaAbreviada,
        // `locale` y no `language` porque lo que viaja es la etiqueta completa
        // —idioma y región—, y porque es el nombre con el que el servicio ya
        // guarda este dato.
        if (idioma != null) 'locale': idioma,
        if (nivelDeApi != null) 'apiLevel': nivelDeApi,
        if (anchoDePantalla != null) 'screenWidth': anchoDePantalla,
        if (altoDePantalla != null) 'screenHeight': altoDePantalla,
        if (densidad != null) 'screenDensity': densidad,
        if (modoOscuro != null) 'darkMode': modoOscuro,
        if (textoAgrandado != null) 'largeText': textoAgrandado,
        if (idiomasPreferidos != null && idiomasPreferidos!.isNotEmpty)
          'preferredLocales': idiomasPreferidos,
        if (reloj24Horas != null) 'clock24h': reloj24Horas,
      };

  /// Lo que la plataforma de Flutter entrega directamente, sin canal nativo.
  ///
  /// Degrada y no falla: perder el modo oscuro cuesta un ícono que se ve mal;
  /// perder el alta cuesta que esa persona no reciba nada.
  static Map<String, dynamic> _delSistema() {
    try {
      final d = PlatformDispatcher.instance;
      final v = d.views.isNotEmpty ? d.views.first : null;
      return {
        if (v != null) 'ancho': v.physicalSize.width.round(),
        if (v != null) 'alto': v.physicalSize.height.round(),
        if (v != null) 'densidad': v.devicePixelRatio,
        'oscuro': d.platformBrightness == Brightness.dark,
        'textoGrande': d.textScaleFactor > 1.15,
        'idiomas': d.locales.map((l) => l.toLanguageTag()).toList(),
        'reloj24': d.alwaysUse24HourFormat,
      };
    } catch (_) {
      return const {};
    }
  }

  static Future<DatosDelDispositivo> recolectar() async {
    final paquete = await _leerPaquete();
    final plataforma = _plataformaActual();

    // Se leen ANTES de tocar el canal nativo y no dentro de cada rama: son
    // cálculos locales que no dependen de que el canal conteste, así que el
    // camino degradado del final los conserva igual que el camino feliz.
    final desfase = DateTime.now().timeZoneOffset.inMinutes;
    final zona = _zonaHorariaAbreviada();
    final idioma = _idiomaDelAparato();
    final sis = _delSistema();

    try {
      final info = DeviceInfoPlugin();

      if (!kIsWeb && Platform.isAndroid) {
        final a = await info.androidInfo;
        return DatosDelDispositivo(
          identificadorDePaquete: paquete.$1,
          plataforma: plataforma,
          deviceId: a.id,
          modelo: a.model,
          fabricante: a.manufacturer,
          marca: a.brand,
          versionDelSistema: a.version.release,
          versionDeLaApp: paquete.$2,
          esFisico: a.isPhysicalDevice,
          nivelDeApi: a.version.sdkInt,
          desfaseUtcMinutos: desfase,
          zonaHorariaAbreviada: zona,
          idioma: idioma,
          anchoDePantalla: sis['ancho'] as int?,
          altoDePantalla: sis['alto'] as int?,
          densidad: sis['densidad'] as double?,
          modoOscuro: sis['oscuro'] as bool?,
          textoAgrandado: sis['textoGrande'] as bool?,
          idiomasPreferidos: (sis['idiomas'] as List?)?.cast<String>(),
          reloj24Horas: sis['reloj24'] as bool?,
        );
      }

      if (!kIsWeb && Platform.isIOS) {
        final i = await info.iosInfo;
        return DatosDelDispositivo(
          identificadorDePaquete: paquete.$1,
          plataforma: plataforma,
          deviceId: i.identifierForVendor,
          modelo: i.utsname.machine,
          fabricante: 'Apple',
          marca: 'Apple',
          versionDelSistema: i.systemVersion,
          versionDeLaApp: paquete.$2,
          esFisico: i.isPhysicalDevice,
          desfaseUtcMinutos: desfase,
          zonaHorariaAbreviada: zona,
          idioma: idioma,
          anchoDePantalla: sis['ancho'] as int?,
          altoDePantalla: sis['alto'] as int?,
          densidad: sis['densidad'] as double?,
          modoOscuro: sis['oscuro'] as bool?,
          textoAgrandado: sis['textoGrande'] as bool?,
          idiomasPreferidos: (sis['idiomas'] as List?)?.cast<String>(),
          reloj24Horas: sis['reloj24'] as bool?,
        );
      }
    } catch (_) {
      // Degrada, no falla. Ver la nota de arriba.
    }

    return DatosDelDispositivo(
      identificadorDePaquete: paquete.$1,
      plataforma: plataforma,
      versionDeLaApp: paquete.$2,
      desfaseUtcMinutos: desfase,
      zonaHorariaAbreviada: zona,
      idioma: idioma,
      anchoDePantalla: sis['ancho'] as int?,
      altoDePantalla: sis['alto'] as int?,
      densidad: sis['densidad'] as double?,
      modoOscuro: sis['oscuro'] as bool?,
      textoAgrandado: sis['textoGrande'] as bool?,
      idiomasPreferidos: (sis['idiomas'] as List?)?.cast<String>(),
      reloj24Horas: sis['reloj24'] as bool?,
    );
  }

  static Future<(String, String?)> _leerPaquete() async {
    try {
      final p = await PackageInfo.fromPlatform();
      return (p.packageName, p.version);
    } catch (_) {
      // Sin identificador de paquete el servidor no puede verificar nada, así
      // que se manda vacío y él decide: es preferible un 400 explicable a
      // inventar un identificador que no es el de esta aplicación.
      return ('', null);
    }
  }

  static String _plataformaActual() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  static String? _zonaHorariaAbreviada() {
    try {
      final nombre = DateTime.now().timeZoneName.trim();
      // Vacío no es un huso: es no saber. Y un campo ausente se distingue de un
      // campo vacío del otro lado; una cadena vacía, no.
      return nombre.isEmpty ? null : nombre;
    } catch (_) {
      return null;
    }
  }

  /// Idioma del aparato, con dos fuentes porque ninguna sirve sola.
  ///
  /// El motor de Flutter es la única que funciona en web, pero contesta `und`
  /// si todavía no le llegó el idioma del sistema —pasa en el arranque más
  /// temprano, que es exactamente cuando corre esto—. El respaldo de `dart:io`
  /// no tiene esa ventana, pero no existe en web.
  static String? _idiomaDelAparato() {
    try {
      final etiqueta = PlatformDispatcher.instance.locale.toLanguageTag();
      if (_esIdiomaUtil(etiqueta)) return etiqueta;
    } catch (_) {
      // Sigue por el respaldo: no saber el idioma nunca puede costar el alta.
    }

    if (!kIsWeb) {
      try {
        // Llega como `es_VE.UTF-8`: la codificación no es parte del idioma, y
        // el guion bajo es la convención POSIX, no la de BCP-47.
        final crudo =
            Platform.localeName.split('.').first.replaceAll('_', '-').trim();
        if (_esIdiomaUtil(crudo)) return crudo;
      } catch (_) {
        // Última fuente: si tampoco está, el campo se omite y listo.
      }
    }

    return null;
  }

  /// `und` es lo que contesta el motor cuando no sabe, y `C`/`POSIX` es la
  /// configuración de un proceso sin idioma. Mandar cualquiera de las tres es
  /// peor que no mandar nada: el servidor las tomaría por un idioma real.
  static bool _esIdiomaUtil(String etiqueta) =>
      etiqueta.isNotEmpty &&
      !etiqueta.startsWith('und') &&
      etiqueta != 'C' &&
      etiqueta != 'POSIX';
}
