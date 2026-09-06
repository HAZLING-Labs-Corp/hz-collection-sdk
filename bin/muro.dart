/// EL MURO DE PERMISOS — la comprobación que falla si algo se coló.
///
/// Se corre así, desde la raíz de CUALQUIER aplicación que instale este SDK:
///
///     dart run hz_collection_sdk:muro
///
/// 🔴 ESTÁ HECHO PARA QUE LO CORRA EL INTEGRADOR, no sólo nosotros. Ése es el punto:
/// el comercio no tiene por qué creernos que no le ensuciamos la ficha de Play — lo
/// comprueba en su propia aplicación, con un comando, antes de publicar.
///
/// Qué hace, en tres restas:
///
///   1. Lee los permisos del manifiesto FUSIONADO (lo que de verdad va a llevar el APK).
///   2. Le resta los que declara la propia aplicación en su manifiesto fuente.
///   3. Lo que queda lo aportaron las dependencias, y **cada uno tiene que tener ficha
///      en el catálogo**. Si aparece uno sin ficha, falla.
///
/// Y además:
///
///   · Si aparece un permiso de la lista de prohibidos, falla diciendo QUÉ POLÍTICA se
///     estaría violando y a quién le sacan la app de la tienda.
///   · Comprueba que toda dependencia con código nativo de iOS traiga su manifiesto de
///     privacidad de Apple. Sin eso, a la aplicación anfitriona le rebotan la subida.
///
/// Devuelve 0 si está limpio y 1 si no, así que sirve tal cual en una tubería de CI.
library;

import 'dart:io';

import 'package:hz_collection_sdk/src/permisologia/catalogo_de_permisos.dart';

const _rojo = '\x1B[31m';
const _verde = '\x1B[32m';
const _amarillo = '\x1B[33m';
const _gris = '\x1B[90m';
const _fin = '\x1B[0m';
const _negrita = '\x1B[1m';

int _fallas = 0;

/// 🔴 EL RUBRO DEL COMERCIO CAMBIA EL VEREDICTO, y por eso el muro lo necesita.
/// `READ_MEDIA_IMAGES` está vetado para una app de préstamo personal y sólo condicionado
/// para una aseguradora. Sin saber el rubro, el muro tendría que elegir entre mentir en
/// contra o dejar pasar de más.
///
/// Se pasa con `--rubro=seguros`. Si no se pasa, queda `sinDeclarar`, que se resuelve al
/// caso MÁS restrictivo: no contestar no puede salir más barato que contestar.
Rubro _rubro = Rubro.sinDeclarar;

void main(List<String> args) {
  final sueltos = <String>[];
  for (final a in args) {
    if (a.startsWith('--rubro=')) {
      final v = a.substring(8);
      _rubro = Rubro.values.firstWhere(
        (r) => r.name.toLowerCase() == v.toLowerCase(),
        orElse: () {
          stdout.writeln('$_rojo  Rubro desconocido: $v$_fin');
          stdout.writeln(
              '$_gris  Los que hay: ${Rubro.values.map((r) => r.name).join(", ")}$_fin');
          exit(2);
        },
      );
    } else {
      sueltos.add(a);
    }
  }
  final raiz = sueltos.isNotEmpty ? sueltos.first : Directory.current.path;

  stdout.writeln('\n$_negrita  EL MURO DE PERMISOS$_fin');
  stdout.writeln('$_gris  $raiz$_fin');
  stdout.writeln('$_gris  rubro: ${_rubro.name}'
      '${_rubro == Rubro.sinDeclarar ? "  ← sin declarar: se aplica el criterio más estricto" : ""}$_fin\n');

  _revisarQueNoHayaCodigoAjeno(raiz);
  _revisarAndroid(raiz);
  _revisarIos(raiz);

  stdout.writeln('');
  if (_fallas == 0) {
    stdout.writeln('$_verde  ✓ Limpio. Nada se coló.$_fin\n');
    exit(0);
  }
  stdout.writeln(
      '$_rojo$_negrita  ✗ $_fallas problema(s). No publiques hasta resolverlos.$_fin\n');
  exit(1);
}

/// 🔴 NINGÚN SDK DE RECOLECCIÓN AJENO ENTRA ACÁ. Ni compilado, ni enlazado, ni copiado.
///
/// La regla la puso Juan el 2026-09-01, y es de las que hay que hacer cumplir con código
/// porque el día que se rompa nadie se va a dar cuenta leyendo un diff: alguien agrega una
/// dependencia para «probar algo» y queda. Nos inspiramos en lo que hace el mercado —qué
/// campos vale la pena mirar es una decisión, y las decisiones no se patentan— pero la
/// implementación es nuestra, escrita contra la API pública de Android, y tiene que poder
/// auditarse renglón por renglón. Una biblioteca compilada de un tercero no se puede auditar
/// y arrastra su licencia adentro.
///
/// Se busca lo único que se puede buscar sin adivinar: **archivos compilados de terceros en
/// el árbol** y **dependencias declaradas con nombre de colector conocido**. No prueba
/// ausencia —nada lo hace—, pero atrapa el caso real, que es el descuido.
void _revisarQueNoHayaCodigoAjeno(String raiz) {
  stdout.writeln('$_negrita  Código ajeno$_fin');

  // El wrapper de Gradle es de Gradle y lo pone Flutter al crear el proyecto; los productos
  // de compilación son nuestros, recién horneados. Ninguno de los dos es una biblioteca de
  // terceros arrastrada a mano, que es lo que se busca.
  bool exento(String ruta) =>
      ruta.contains('/build/') ||
      ruta.contains('/.dart_tool/') ||
      ruta.contains('gradle/wrapper/gradle-wrapper.jar') ||
      ruta.contains('/Pods/');

  final compilados = <String>[];
  final dir = Directory(raiz);
  if (dir.existsSync()) {
    for (final f in dir.listSync(recursive: true, followLinks: false)) {
      if (f is! File) continue;
      final r = f.path;
      if (exento(r)) continue;
      if (r.endsWith('.jar') ||
          r.endsWith('.aar') ||
          r.endsWith('.dex') ||
          r.endsWith('.smali') ||
          r.endsWith('.xcframework')) {
        compilados.add(r.replaceFirst(raiz, '.'));
      }
    }
  }

  // Los nombres de los colectores del mercado, para el caso en que alguien declare uno como
  // dependencia. La lista es corta a propósito: es una red de seguridad para el descuido, no
  // un censo del sector.
  const ajenos = [
    'credolab', 'credo_lab', 'lenddo', 'juicescore', 'trustingsocial',
    'threatmetrix', 'seon', 'sift', 'socure', 'biocatch', 'fingerprintjs',
  ];
  final declaradas = <String>[];
  final pub = File('$raiz/pubspec.yaml');
  if (pub.existsSync()) {
    for (final linea in pub.readAsLinesSync()) {
      final l = linea.trim().toLowerCase();
      if (l.startsWith('#')) continue;
      for (final a in ajenos) {
        if (l.contains(a)) declaradas.add(linea.trim());
      }
    }
  }

  if (compilados.isEmpty && declaradas.isEmpty) {
    stdout.writeln('$_verde    ✓ Nada compilado de terceros y ninguna dependencia de otro '
        'colector$_fin');
    return;
  }

  _fallas += compilados.length + declaradas.length;
  for (final c in compilados) {
    stdout.writeln('$_rojo$_negrita    ✗ Archivo compilado de terceros: $c$_fin');
  }
  for (final d in declaradas) {
    stdout.writeln('$_rojo$_negrita    ✗ Dependencia de otro colector declarada: $d$_fin');
  }
  stdout.writeln('$_gris      Nos inspiramos en lo que hace el mercado; no usamos su código.$_fin');
  stdout.writeln('$_gris      La implementación se escribe contra la API pública de Android.$_fin');
}

/// 🔴 EL MANIFIESTO DE ESTE PAQUETE — la comprobación que no necesita compilar nada.
///
/// Cuando `hz_collection_sdk` pasó a tener código nativo (2026-09-01, para alcanzar las
/// señales de nivel 0 que desde Dart no se ven), apareció un archivo que **no existía
/// antes**: `android/src/main/AndroidManifest.xml`. Un permiso escrito ahí se le inyecta a
/// TODA aplicación que instale el SDK, la use o no, y la aplicación se entera cuando Play
/// le rechaza la subida. Es exactamente lo que se le midió a CredoLab, cuyos paquetes le
/// meten READ_CONTACTS y READ_CALENDAR a cualquiera que los instale.
///
/// La primera versión del muro no lo miraba: sólo revisaba el manifiesto de una APLICACIÓN
/// (`android/app/...`), y corrido desde la raíz del paquete decía «sin proyecto Android acá
/// — se saltea» y daba verde. **Verde sobre el archivo más peligroso del repositorio.** Lo
/// encontró correr el muro después de agregar el código nativo, no una revisión.
///
/// Ésta corre siempre, sin compilar y sin proyecto de aplicación, que es lo que hace que se
/// corra de verdad.
void _revisarElManifiestoDeEstePaquete(String raiz) {
  final f = File('$raiz/android/src/main/AndroidManifest.xml');
  if (!f.existsSync()) return; // este paquete no tiene código nativo: no hay nada que inyectar

  final permisos = _permisosDe(f.readAsStringSync());
  if (permisos.isEmpty) {
    stdout.writeln(
        '$_verde    ✓ El manifiesto del paquete no declara permisos$_fin'
        '$_gris  (no le inyecta nada a quien lo instale)$_fin');
    return;
  }

  _fallas += permisos.length;
  stdout.writeln('$_rojo$_negrita    ✗ El manifiesto de ESTE paquete declara '
      '${permisos.length} permiso(s)$_fin');
  for (final p in permisos) {
    stdout.writeln('$_rojo      · $p$_fin');
  }
  stdout.writeln('$_gris      Un permiso acá se le inyecta a TODA aplicación que instale el$_fin');
  stdout.writeln('$_gris      SDK, lo use o no. Va en el manifiesto de la aplicación que lo$_fin');
  stdout.writeln('$_gris      necesita, nunca acá. Ver android/src/main/AndroidManifest.xml.$_fin');
}

// ─────────────────────────────────────────────────────────────────────────────────
// ANDROID
// ─────────────────────────────────────────────────────────────────────────────────

void _revisarAndroid(String raiz) {
  stdout.writeln('$_negrita  Android$_fin');

  _revisarElManifiestoDeEstePaquete(raiz);

  final propio = File('$raiz/android/app/src/main/AndroidManifest.xml');
  if (!propio.existsSync()) {
    stdout.writeln('$_gris    sin proyecto Android acá — se saltea$_fin');
    return;
  }

  final declaraLaApp = _permisosDe(propio.readAsStringSync());
  final fusionado = _manifiestoFusionado(raiz);

  if (fusionado == null) {
    // 🔴 No se falla por esto, y es a propósito: el manifiesto fusionado sólo existe
    // después de compilar. Fallar acá obligaría a compilar para poder correr el muro, y
    // entonces nadie lo correría. Se revisa lo que hay y se dice qué falta para el resto.
    stdout.writeln('$_amarillo    ⚠ No hay manifiesto fusionado todavía.$_fin');
    stdout.writeln(
        '$_gris      Compilá una vez (flutter build apk --debug) y volvé a correr esto$_fin');
    stdout.writeln(
        '$_gris      para revisar también lo que aportan las dependencias.$_fin');
    _revisarLista(declaraLaApp, 'la aplicación');
    return;
  }

  final enElApk = _permisosDe(fusionado);

  // 🔴 SE APARTAN LOS QUE LA PROPIA APP SE AUTOGENERA, y no es una excepción cómoda.
  // AndroidX crea permisos con el nombre del paquete adentro
  // —`com.tuapp.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`— para que ninguna otra
  // aplicación pueda escuchar sus avisos internos. Son de seguridad, no se le muestran
  // a nadie, y llevan el paquete adentro, así que JAMÁS pueden estar en un catálogo
  // estático: cambian con cada app. Tratarlos como «sin ficha» haría que el muro diera
  // rojo en todas las aplicaciones del mundo, y un muro que siempre da rojo se apaga.
  final paquete = _paqueteDe(fusionado);
  final propios = paquete == null
      ? <String>{}
      : enElApk.where((p) => p.startsWith('$paquete.')).toSet();

  final loAportanDependencias =
      enElApk.difference(declaraLaApp).difference(propios);

  stdout.writeln(
      '$_gris    ${enElApk.length} en el APK · ${declaraLaApp.length} los declara la app · '
      '${loAportanDependencias.length} los aportan las dependencias'
      '${propios.isEmpty ? "" : " · ${propios.length} se los autogenera la app"}$_fin\n');

  _revisarLista(declaraLaApp, 'la aplicación');
  _revisarLista(loAportanDependencias, 'una dependencia');
}

/// Revisa un grupo de permisos contra el catálogo y contra la lista de prohibidos.
void _revisarLista(Set<String> permisos, String quienLoAporta) {
  if (permisos.isEmpty) return;

  for (final p in permisos.toList()..sort()) {
    final prohibido = permisosProhibidos[p];
    if (prohibido != null) {
      _fallas++;
      stdout.writeln('$_rojo    ✗ $p$_fin');
      stdout.writeln('$_rojo      PROHIBIDO. $prohibido$_fin');
      stdout.writeln(
          '$_rojo      Lo aporta: $quienLoAporta. Sacalo antes de publicar.$_fin\n');
      continue;
    }

    final ficha = fichaDe(p);
    if (ficha == null) {
      _fallas++;
      stdout.writeln('$_rojo    ✗ $p$_fin');
      stdout.writeln('$_rojo      Sin ficha en el catálogo. Lo aporta: $quienLoAporta.$_fin');
      stdout.writeln(
          '$_gris      Si tiene que estar, declaralo en catalogo_de_permisos.dart con su$_fin');
      stdout.writeln(
          '$_gris      módulo, para qué sirve, cuánto se retiene y con qué base legal.$_fin\n');
      continue;
    }

    final corto = p.replaceFirst('android.permission.', '');
    final n = switch (ficha.nivel) {
      Nivel.ninguno => '${_gris}nivel 0$_fin',
      Nivel.comun => '${_gris}nivel 1$_fin',
      Nivel.asusta => '$_amarillo nivel 2 · asusta en la ficha de la tienda$_fin',
      Nivel.revisionManual => '$_rojo nivel 3 · lo revisa la tienda a mano$_fin',
    };

    // El veredicto sale de `estadoPara`, que encadena el rubro y la puerta de dato
    // sensible en el orden correcto. Consultarlas por separado acá dejaría abierta la
    // posibilidad de mirar una y olvidarse de la otra.
    switch (ficha.estadoPara(_rubro)) {
      case Estado.prohibido:
        _fallas++;
        stdout.writeln('$_rojo    ✗ $corto$_fin');
        stdout.writeln('$_rojo      PROHIBIDO para el rubro «${_rubro.name}».$_fin');
        stdout.writeln('$_rojo      ${ficha.porQuePara(_rubro)}$_fin\n');
      case Estado.condicionado:
        stdout.writeln('$_amarillo    ⚠$_fin $corto  $n');
        stdout.writeln('$_gris      ${ficha.modulo} · ${ficha.paraQue}$_fin');
        stdout.writeln('$_amarillo      Se puede, pero hay que hacer esto:$_fin');
        for (final r in ficha.requisitos) {
          stdout.writeln('$_amarillo      · ${r.queHacer}$_fin');
          stdout.writeln('$_gris        ${r.fuente}$_fin');
        }
        stdout.writeln('');
      case Estado.libre:
        stdout.writeln('$_verde    ✓$_fin $corto  $n');
        stdout.writeln('$_gris      ${ficha.modulo} · ${ficha.paraQue}$_fin');
    }
  }
  stdout.writeln('');
}

/// El nombre del paquete de la aplicación, del atributo `package` del manifiesto.
/// Hace falta para reconocer los permisos que ella misma se autogenera.
String? _paqueteDe(String xml) =>
    RegExp(r'\bpackage\s*=\s*"([^"]+)"').firstMatch(xml)?.group(1);

/// Saca los `android:name` de todos los `<uses-permission>` de un manifiesto.
///
/// Se hace con una expresión regular y no con un parser de XML a propósito: el
/// manifiesto fusionado trae comentarios, atributos de herramientas y espacios de
/// nombres que a un parser estricto lo hacen fallar, y acá sólo hacen falta los nombres.
///
/// 🔴 LOS COMENTARIOS SE SACAN PRIMERO, Y ESO ES UN ARREGLO, NO UNA OPTIMIZACIÓN.
///
/// Hasta el 2026-09-05 la expresión corría sobre el archivo entero, así que **un permiso
/// nombrado dentro de un comentario contaba como declarado**. Se descubrió el mismo día, al
/// documentar en el manifiesto de este paquete los tres permisos de la ubicación en segundo
/// plano —para que el integrador sepa cuáles son y por qué NO van ahí—: el muro dio rojo
/// sobre un archivo que no declara ni uno.
///
/// Importa más de lo que parece. El caso normal de un integrador es dejar un
/// `<!-- <uses-permission ...> -->` comentado mientras decide, y ahí el muro lo acusaría de
/// declarar algo que el APK no lleva. Android ignora los comentarios al fusionar; el muro
/// tiene que hacer lo mismo o miente. Y un muro que grita en falso se apaga — es la misma
/// razón por la que iOS avisa en vez de fallar, unas líneas más abajo.
Set<String> _permisosDe(String xml) => RegExp(
      r'<uses-permission[^>]*android:name\s*=\s*"([^"]+)"',
      multiLine: true,
    ).allMatches(_sinComentarios(xml)).map((m) => m.group(1)!).toSet();

/// Borra los comentarios XML —`<!-- … -->`, también los de varias líneas—. Ver la nota de
/// [_permisosDe].
String _sinComentarios(String xml) =>
    xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// Busca el manifiesto fusionado de la APLICACIÓN, que es el único que importa.
///
/// 🔴 Se descartan los de los módulos (`build/<paquete>/...`): cada dependencia genera
/// el suyo, y si se leyera cualquiera, el muro estaría revisando el manifiesto de una
/// librería suelta en vez del que va a terminar en el APK. Es un error fácil de cometer
/// y silencioso — daría verde sobre el archivo equivocado.
String? _manifiestoFusionado(String raiz) {
  final dir = Directory('$raiz/build/app/intermediates/merged_manifests');
  final candidatos = <File>[];

  for (final base in [
    Directory('$raiz/build/app/intermediates/merged_manifests'),
    Directory('$raiz/build/app/intermediates/merged_manifest'),
  ]) {
    if (!base.existsSync()) continue;
    candidatos.addAll(base
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('AndroidManifest.xml')));
  }
  if (candidatos.isEmpty && dir.existsSync()) return null;
  if (candidatos.isEmpty) return null;

  // El más reciente: si hay debug y release, vale el último que se compiló.
  candidatos.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  return candidatos.first.readAsStringSync();
}

// ─────────────────────────────────────────────────────────────────────────────────
// iOS
// ─────────────────────────────────────────────────────────────────────────────────

/// Comprueba que toda dependencia con código nativo de iOS traiga su manifiesto de
/// privacidad.
///
/// 🔴 POR QUÉ ESTO PUEDE HACER QUE LE REBOTEN LA APP AL INTEGRADOR: desde 2024 Apple
/// exige que cada SDK de terceros declare qué datos recoge y por qué usa ciertas APIs.
/// Si una dependencia no trae su `PrivacyInfo.xcprivacy`, el rechazo no le llega al
/// autor de la dependencia: le llega a quien intentó subir la aplicación.
void _revisarIos(String raiz) {
  stdout.writeln('$_negrita  iOS$_fin');

  final cache = _cacheDePaquetes(raiz);
  if (cache.isEmpty) {
    stdout.writeln('$_gris    no se pudo leer la lista de paquetes — se saltea$_fin');
    return;
  }

  final sinManifiesto = <String>[];
  var conNativo = 0;

  for (final entrada in cache.entries) {
    final ios = Directory('${entrada.value}/ios');
    final darwin = Directory('${entrada.value}/darwin');
    final carpeta = ios.existsSync() ? ios : (darwin.existsSync() ? darwin : null);
    if (carpeta == null) continue;

    final archivos = carpeta.listSync(recursive: true).whereType<File>().toList();

    // 🔴 TENER CARPETA `ios/` NO ES TENER CÓDIGO NATIVO. Varios paquetes traen sólo un
    // `.podspec` que declara una dependencia y nada más — el de la versión web de
    // Firebase, por ejemplo. Apple no le pide manifiesto a eso, y marcarlo era un falso
    // positivo del muro en su primera corrida, el 2026-08-31. Se exige código de verdad.
    final tieneFuentes = archivos.any((f) =>
        f.path.endsWith('.m') ||
        f.path.endsWith('.mm') ||
        f.path.endsWith('.swift') ||
        f.path.endsWith('.h'));
    if (!tieneFuentes) continue;
    conNativo++;

    final tiene = archivos.any((f) => f.path.endsWith('PrivacyInfo.xcprivacy'));
    if (!tiene) sinManifiesto.add(entrada.key);
  }

  stdout.writeln('$_gris    $conNativo paquete(s) con código nativo de iOS$_fin');

  if (sinManifiesto.isEmpty) {
    stdout.writeln('$_verde    ✓ todos traen su manifiesto de privacidad$_fin');
    return;
  }
  // 🔴 AVISA, NO FALLA — y la diferencia está pensada. Un envoltorio de Flutter con
  // código nativo propio sólo necesita manifiesto si toca alguna de las APIs que Apple
  // obliga a justificar, y eso no se puede saber leyendo nombres de archivo: casi
  // siempre el manifiesto lo trae el pod del que depende. Fallar acá haría que el muro
  // diera rojo por algo que en la mayoría de los casos está bien — y un muro que grita
  // en falso se termina apagando, que es exactamente lo que no queremos.
  stdout.writeln(
      '$_amarillo    ⚠ ${sinManifiesto.length} paquete(s) sin PrivacyInfo.xcprivacy propio$_fin');
  for (final p in sinManifiesto..sort()) {
    stdout.writeln('$_amarillo      · $p$_fin');
  }
  stdout.writeln(
      '$_gris      Casi siempre el manifiesto lo trae el pod del que dependen. Antes de$_fin');
  stdout.writeln(
      '$_gris      subir a la App Store, confirmalo con quien compile en Xcode.$_fin');
}

/// Dónde está en disco cada paquete del que depende este proyecto.
///
/// Se lee de `.dart_tool/package_config.json`, que es el archivo que genera
/// `pub get` y que dice exactamente qué versión se está usando — no lo que pide el
/// `pubspec.yaml`, que puede ser un rango.
Map<String, String> _cacheDePaquetes(String raiz) {
  final f = File('$raiz/.dart_tool/package_config.json');
  if (!f.existsSync()) return {};
  final salida = <String, String>{};

  // Se parsea a mano con una expresión regular para no depender de `dart:convert` en un
  // archivo que tiene que poder correr en un entorno mínimo de CI.
  final texto = f.readAsStringSync();
  for (final m in RegExp(
    r'"name"\s*:\s*"([^"]+)"[^}]*?"rootUri"\s*:\s*"([^"]+)"',
    dotAll: true,
  ).allMatches(texto)) {
    final nombre = m.group(1)!;
    var ruta = m.group(2)!;
    if (ruta.startsWith('file://')) ruta = Uri.parse(ruta).toFilePath();
    if (ruta.startsWith('../')) ruta = '$raiz/.dart_tool/$ruta';
    salida[nombre] = ruta;
  }
  return salida;
}
