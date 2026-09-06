import 'dart:convert';

import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import 'la_solicitud.dart';
import 'lo_recolectado.dart';
import 'nucleo.dart';

/// El `10.0.2.2` es cómo un emulador de Android alcanza el localhost de la
/// máquina que lo hospeda.
///
/// 🔴 EL PUERTO POR OMISIÓN ES 3085 — el back de Collection (`hz-collection-tiers-back`),
/// que es el único que tiene la ruta `POST /api/v1/ubicacion`. Antes apuntaba a 3096, que
/// es `ak-push-back` —el repo viejo, abandonado— donde esa ruta no existe: un `flutter run`
/// sin `--dart-define` mandaba las coordenadas a un back que contesta 404, y como
/// `reportarUbicacion` se traga el error, no se veía nada. La app quedaba «midiendo bien y
/// sin enviar» por apuntar al servidor equivocado. El README ya documenta 3085; esto lo
/// hace coincidir con el default.
const _llave = String.fromEnvironment('AKPUSH_KEY', defaultValue: 'pk_demo.local');
const _url = String.fromEnvironment('AKPUSH_URL', defaultValue: 'http://10.0.2.2:3085/api/v1');

/// 🔴 ESTO NO VA EN UNA APLICACIÓN DE VERDAD. NUNCA.
///
/// El secreto con el que se firma el `userId` vive en el **backend** del
/// comercio, y la aplicación recibe la firma ya calculada junto con la sesión.
/// Ponerlo acá lo hace tan legible como la llave para cualquiera que descomprima
/// el APK — y entonces la firma deja de probar nada, que es exactamente el
/// agujero que la verificación de identidad viene a cerrar.
///
/// Está sólo para poder probar los modos AVISA y EXIGIDA de punta a punta sin
/// levantar un backend de mentira. Se pasa por `--dart-define` y si no viene, no
/// se firma nada.
const _secretoDePrueba = String.fromEnvironment('AKPUSH_SECRETO_DE_PRUEBA');

/// Lo que haría el backend del comercio: HMAC-SHA256 del userId, en hexadecimal.
String? _firmarComoLoHariaElBackend(String userId) {
  if (_secretoDePrueba.isEmpty) return null;
  return Hmac(sha256, utf8.encode(_secretoDePrueba))
      .convert(utf8.encode(userId))
      .toString();
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        // 🔴 LA ÚNICA LÍNEA QUE ESTA APLICACIÓN ESCRIBE PARA LA UBICACIÓN.
        //
        // Con esto el SDK ya puede levantar sus propias pantallas: al iniciar sesión
        // ofrece la ubicación con su modal, usando los textos que este comercio
        // configuró en la consola. Sin esta línea todo lo demás anda igual, pero el
        // modal no tiene dónde dibujarse y no aparece.
        navigatorKey: AkPush.navegador,
        title: 'Collection',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2D5F8A)),
          useMaterial3: true,
        ),
        home: const Pantalla(),
      );
}

class Pantalla extends StatefulWidget {
  const Pantalla({super.key});
  @override
  State<Pantalla> createState() => _PantallaState();
}

class _PantallaState extends State<Pantalla> {
  final List<String> _bitacora = [];

  /// Qué pestaña se está mirando: 0 sesión · 1 datos · 2 ubicación · 3 solicitud.
  int _vista = 0;
  String _estado = 'iniciando…';
  String? _token;
  PersonaDelNucleo? _dentro;
  ResultadoDeSesion? _sesion;

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  void _anotar(String l) {
    if (!mounted) return;
    setState(() => _bitacora.insert(0, '${TimeOfDay.now().format(context)}  $l'));
  }

  Future<void> _arrancar() async {
    try {
      // El permiso NO se pide acá: lo decide la política del comercio cuando la
      // persona inicia sesión. Es el momento en que ya sabe qué es la app.
      await AkPush.init(
        llave: _llave,
        url: _url,
        pedirPermisoAlIniciar: false,
      );
      setState(() {
        _estado = 'listo';
        _token = AkPush.token;
      });
      // El comercio no se configura: la configuración lo dice.
      _anotar('configuración de ${AkPush.comercio} · política: '
          '${AkPush.politica.momento.name}');

      AkPush.onMessage.listen((m) => _anotar('llegó: ${m.title ?? "(sin título)"}'));
      AkPush.onNotificationTap.listen((m) => _anotar('tocado: ${m.title ?? m.codeEvent ?? "?"}'));
    } on AkPushError catch (e) {
      setState(() => _estado = 'falló: ${e.code.name}');
      _anotar('${e.message}${e.details != null ? " — ${e.details}" : ""}');
    }
  }

  Future<void> _entrar(PersonaDelNucleo p) async {
    _anotar('entrando como ${p.nombre} · ${p.cedula}');
    try {
      final r = await AkPush.alIniciarSesion(
        userId: p.uuid,
        // Es una empresa, o una persona natural — para las dos empresas del
        // juego de prueba esto sale en `TipoDeSujeto.juridica`.
        tipo: p.tipo,
        // El documento. Es lo que le permite a un sistema de afuera pedir un envío
        // sin conocer el `userId` interno del comercio — que no tiene por qué
        // conocer. Reemplaza a la vieja `identity`: ahora declara también la CLASE
        // (cédula, RIF, pasaporte), no sólo el número.
        documento: p.documento,
        // La organización a la que pertenece, si tiene una — los dos empleados de
        // proveedor del juego de prueba la traen puesta.
        organizacion: p.organizacion,
        identityHash: _firmarComoLoHariaElBackend(p.uuid),
        // 🔴 LO QUE EL COMERCIO SABE DE ESTA PERSONA, y que el servicio no puede
        // inventar. Sin esto la consola muestra `u_9000` y nada más: no se puede
        // buscar a nadie por su nombre, ni segmentar un envío por sucursal o por plan.
        //
        // No hay que declarar estos campos en ningún lado: el servicio los DESCUBRE
        // de lo que llega y arma los filtros solo. Cada comercio manda los suyos.
        /// 🔴 SÓLO LAS COLUMNAS DEL EXCEL — corregido por Juan el 2026-09-04:
        /// *«esos no son datos míos, yo tengo un UUID o un identificador; apegate a lo que
        /// tengo en el Excel»*.
        ///
        /// Salieron `usuario`, `sucursal` y `plan`, que venían del juego de prueba viejo.
        /// Inventar columnas que el archivo no tiene es cómo una prueba deja de probar el
        /// caso real: se filtra por una sucursal que en la cartera de verdad no existe, y el
        /// filtro pasa igual.
        datos: {
          'nombre': p.nombre,
          'correo': p.correo,
          'ciudad': p.ciudad,
          // Los cuatro que trajo la reconciliación con notificaciones (2026-09-04).
          //
          // 🔴 El teléfono va acá, con los datos, y NO entre los identificadores: la
          // identidad es el documento. Un teléfono lo pueden compartir dos personas, así
          // que no identifica a nadie — y Collection manda push, que va al token del
          // aparato y nunca a un número. Quien direcciona por teléfono es notificaciones, y
          // allá el teléfono ya tiene su rol declarado.
          if (p.telefono.isNotEmpty) 'telefono': p.telefono,
          if (p.pais.isNotEmpty) 'pais': p.pais,
          if (p.estado.isNotEmpty) 'estado': p.estado,
          if (p.genero.isNotEmpty) 'genero': p.genero,
        },
      );
      setState(() {
        _dentro = p;
        _sesion = r;
        _token = AkPush.token;
      });
      _anotar('${r.motivo}  ·  ${AkPush.consentimiento.punto}');

      // La pregunta blanda es de la app, no del SDK: el SDK sólo avisa cuándo.
      if (r.accionSugerida == AccionDePermiso.mostrarPreguntaBlanda) {
        await _preguntaBlanda();
      } else if (r.accionSugerida == AccionDePermiso.ofrecerAjustes) {
        _anotar('sólo quedan los Ajustes del teléfono');
      }
    } on AkPushError catch (e) {
      _anotar('no se pudo entrar: ${e.code.name}');
      if (e.code == AkPushErrorCode.firmaDeIdentidad) {
        _anotar('el comercio exige el userId firmado — pasá '
            '--dart-define=AKPUSH_SECRETO_DE_PRUEBA=…');
      }
    }
  }


  /// Pide la ubicación y manda la posición.
  ///
  /// Primero se explica para qué sirve y recién después sale el diálogo del
  /// sistema: el permiso que se pide sin explicar es el que se deniega, y en
  /// Android un «no» al de ubicación tampoco se vuelve a preguntar solo.
  Future<void> _preguntaBlanda() async {
    final t = AkPush.politica.textos;
    final si = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.titulo),
        content: Text(t.cuerpo),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.ahoraNo)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t.aceptar)),
        ],
      ),
    );
    // Se marca en los DOS casos, no sólo cuando acepta: un «ahora no» es el dato
    // que distingue a quien se puede recuperar de quien ya dijo que no de verdad.
    await AkPush.reportarModal(acepto: si == true);

    if (si != true) {
      _anotar('dijo «ahora no» — el diálogo del sistema no se gastó');
      return;
    }
    final e = await AkPush.pedirPermiso();
    _anotar('permiso: ${e.name}');
    if (_dentro != null) await _entrar(_dentro!);
  }

  Future<void> _salir() async {
    await AkPush.alCerrarSesion();
    setState(() { _dentro = null; _sesion = null; });
    _anotar('sesión cerrada · el teléfono quedó sin dueño');
  }

  Future<void> _elegirPersona() async {
    final p = await showModalBottomSheet<PersonaDelNucleo>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _Entrada(),
    );
    if (p != null) await _entrar(p);
  }

  Future<void> _verDiagnostico() async {
    final d = await AkPush.diagnostico();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Diagnóstico'),
        content: SingleChildScrollView(child: Text(d.toString())),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final r = _sesion;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collection'),
        backgroundColor: t.colorScheme.inversePrimary,
        actions: [
          // 🔴 LA CAMPANITA — una línea, y viene hecha del SDK.
          //
          // Muestra un punto rojo cuando los avisos están apagados, explica al tocarla,
          // y ofrece el único botón que puede arreglarlo en ese estado: pedir el permiso
          // si el sistema todavía pregunta, o abrir los ajustes del teléfono si ya no.
          // Se actualiza sola cuando la persona vuelve de los Ajustes.
          //
          // Quien prefiera dibujar la suya tiene los mismos servicios sueltos:
          // AkPush.avisos · AkPush.estadoDeAvisos() · AkPush.resolverAvisos()
          AkPush.campanita(
            alResolver: (e) => _anotar('avisos: ${e.titulo.toLowerCase()}'),
          ),
          IconButton(
            onPressed: _verDiagnostico,
            icon: const Icon(Icons.medical_information_outlined),
            tooltip: 'Diagnóstico',
          ),
        ],
      ),
      // ── LAS TRES VISTAS ────────────────────────────────────────────────────
      //
      // «Sesión» es lo que había: el estado y quién entró. Las otras dos son para VER lo
      // que se recolecta — y eso no es una comodidad de la demo: un colector que no le
      // deja mirar a la persona qué se llevó es lo que hace que la gente desconfíe.
      bottomNavigationBar: NavigationBar(
        selectedIndex: _vista,
        onDestinationSelected: (i) => setState(() => _vista = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge),
            label: 'Sesión'),
          NavigationDestination(
            icon: Icon(Icons.storage_outlined),
            selectedIcon: Icon(Icons.storage),
            label: 'Datos'),
          NavigationDestination(
            icon: Icon(Icons.place_outlined),
            selectedIcon: Icon(Icons.place),
            label: 'Ubicación'),
          // 🔴 «Solicitud» es la pestaña donde se prueba el comportamiento, y tiene que
          // estar en la pantalla y no en una prueba: el tiempo de llenado, el abandono y
          // el «pegó o escribió» sólo existen si hay dedos sobre un formulario de verdad.
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Solicitud'),
        ],
      ),
      body: _vista == 1
          ? const LoRecolectado()
          : _vista == 2
              ? const DondeEstuvo()
              : _vista == 3
              ? const LaSolicitud()
              : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Estado', style: t.textTheme.labelMedium),
                  Text(_estado, style: t.textTheme.headlineSmall),
                  if (_dentro != null) ...[
                    const SizedBox(height: 10),
                    Text(_dentro!.nombre,
                        style: t.textTheme.titleMedium),
                    // 🔴 CADA COSA CON SU ROTULO. Al poner el identificador acá quedó
                    // pegado al rótulo «cédula» que ya estaba: la ficha decía
                    // «cédula 676dc59e8cc125da8f90e289», que es el uuid, mientras la
                    // cédula de verdad —17229393— salía en el renglón de abajo sin
                    // rótulo. Dos identificadores distintos con el nombre del otro, en la
                    // pantalla que se mira para saber con quién se entró.
                    Text(
                        'identificador ${_dentro!.uuid}\n'
                        '${_dentro!.tipo == TipoDeSujeto.juridica ? "RIF" : "cédula"} '
                        '${_dentro!.cedula} · ${_dentro!.estado}',
                        style: t.textTheme.bodySmall),
                    // Sólo aparece para los empleados de proveedor del juego de
                    // prueba: es lo que demuestra que el sujeto PERTENECE a la
                    // organización sin dejar de ser él mismo.
                    if (_dentro!.organizacion != null)
                      Text('de ${_dentro!.organizacion}',
                          style: t.textTheme.bodySmall
                              ?.copyWith(fontStyle: FontStyle.italic)),
                  ],
                  if (r != null) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Icon(r.puedeRecibir ? Icons.check_circle : Icons.cancel,
                          size: 18,
                          color: r.puedeRecibir ? Colors.green.shade700 : Colors.orange.shade800),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(r.puedeRecibir ? 'Puede recibir' : 'No puede recibir',
                            style: t.textTheme.titleSmall),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(r.motivo, style: t.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 12),
                  Text('Dirección de este teléfono', style: t.textTheme.labelMedium),
                  Text(_token == null ? '—' : '${_token!.substring(0, 22)}…',
                      style: t.textTheme.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _elegirPersona,
                icon: const Icon(Icons.person_search),
                label: Text(_dentro == null ? 'Entrar' : 'Cambiar de persona'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _dentro == null ? null : _salir,
                child: const Text('Salir'),
              ),
            ),
          ]),
          // ── La ubicación la ofrece el SDK, no esta pantalla ─────────────
          //
          // 🔴 Acá NO hay ningún botón, y es a propósito: este archivo es el ejemplo
          // de lo que un comercio tiene que escribir para usar el SDK, y la respuesta
          // es «nada». El SDK levanta su propio modal al iniciar sesión —con los textos
          // que ese comercio configuró en la consola— siempre que le hayan prestado el
          // `navigatorKey` al `MaterialApp`, que es la única línea que hace falta.
          //
          // Si un comercio prefiere ofrecerla en otro momento —al abrir el mapa de
          // sucursales, digamos, que es cuando más gente acepta— pone el momento en
          // «laAppDecide» desde la consola y llama a `AkPush.ofrecerUbicacion(context)`
          // donde quiera.
          // ── QUÉ MODO DE UBICACIÓN QUEDÓ ANDANDO ────────────────────────
          //
          // 🔴 Está a la vista y no escondido en el diagnóstico porque el fallo que
          // esta línea existe para mostrar no se parece a un error: el comercio prende
          // «segundo plano» en su consola, no pasa nada, y sin esto no hay forma de
          // enterarse de que a la aplicación le falta un renglón en su manifiesto.
          if (AkPush.modoDeUbicacionPedido != ModoDeLectura.alEntrar) ...[
            const SizedBox(height: 16),
            _LineaDeUbicacion(),
          ],
          const SizedBox(height: 20),
          Text('Bitácora', style: t.textTheme.labelMedium),
          const Divider(),
          if (_bitacora.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('Todavía no pasó nada', style: t.textTheme.bodySmall)),
            ),
          for (final l in _bitacora)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(l, style: t.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// LA PUERTA — usuario y clave contra el núcleo del comercio
/// ═══════════════════════════════════════════════════════════════════════════
///
/// 🔴 QUÉ CAMBIÓ, Y POR QUÉ · 2026-09-05
///
/// Acá había un selector que listaba `cienPersonas`, una constante compilada
/// dentro del APK. Se tocaba un nombre y se entraba: **sin clave**. Dos
/// problemas, y ninguno es de estilo:
///
/// 1. Para corregir una cédula, agregar una empresa o arreglar un correo había
///    que **recompilar y volver a repartir el APK**. El juego de prueba era
///    intocable, que es lo contrario de un juego de prueba.
/// 2. Elegir de una lista no es entrar. Un sistema de verdad pide usuario y
///    clave, y la app de prueba tiene que probar ese camino, no uno inventado.
///
/// Ahora las personas viven en `hz-mundototal-core`, el sistema de origen del
/// comercio. La app **no guarda copia**: si el núcleo no contesta, esta pantalla
/// dice qué ruta falta en vez de fingir que tiene gente.
///
/// El directorio lo protege el núcleo, así que hay que presentarle una credencial.
/// Son dos, y no es lo mismo:
///
/// - **La llave de la aplicación** (`--dart-define=NUCLEO_LLAVE=mtk_…`): la trae el
///   APK compilado. Con ella el directorio se ve de entrada y **tocar un nombre
///   entra** — sin usuario ni clave. Es lo que Juan pidió el 2026-09-05 para el
///   APK de demostración.
/// - **La sesión de una persona**: cuando la copia se compiló sin llave. Ahí el
///   directorio recién aparece después de entrar.
class _Entrada extends StatefulWidget {
  @override
  State<_Entrada> createState() => _EntradaState();
}

class _EntradaState extends State<_Entrada> {
  final _usuario = TextEditingController();
  final _clave = TextEditingController();
  final _busqueda = TextEditingController();

  String? _error;
  bool _entrando = false;

  List<PersonaDelNucleo>? _directorio;
  bool _cargandoDirectorio = false;
  String? _errorDirectorio;

  /// ¿Esta copia se compiló con su propia llave de consulta al núcleo?
  ///
  /// Es lo que decide la pantalla entera: con llave, el directorio manda y tocar
  /// un nombre entra. Sin llave, no hay de dónde sacar la lista antes de tener
  /// sesión, así que primero hay que entrar con usuario y clave.
  bool get _conLlave => nucleoLlave.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Con llave de aplicación el directorio se puede ver ANTES de entrar: es lo que
    // permite elegir con quién entrar sin conocer a nadie de antemano. Sin llave,
    // sólo si ya hay sesión de una vuelta anterior.
    if (_conLlave || Nucleo.token != null) _traerDirectorio();
  }

  @override
  void dispose() {
    _usuario.dispose();
    _clave.dispose();
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _traerDirectorio() async {
    setState(() { _cargandoDirectorio = true; _errorDirectorio = null; });
    try {
      final gente = await Nucleo.directorio(busqueda: _busqueda.text.trim());
      if (!mounted) return;
      setState(() { _directorio = gente; _cargandoDirectorio = false; });
    } on ErrorDelNucleo catch (e) {
      if (!mounted) return;
      setState(() {
        _errorDirectorio = e.toString();
        _cargandoDirectorio = false;
        _directorio = null;
      });
    }
  }

  Future<void> _entrar() async {
    setState(() { _entrando = true; _error = null; });
    try {
      final p = await Nucleo.entrar(_usuario.text.trim(), _clave.text);
      if (!mounted) return;
      Navigator.pop(context, p);
    } on ErrorDelNucleo catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _entrando = false; });
    }
  }

  /// El formulario de usuario y clave.
  ///
  /// Sigue existiendo con llave compilada, pero abajo y plegado: es el único camino
  /// que prueba `POST /auth/login` del núcleo de verdad, y borrarlo dejaría esa ruta
  /// sin nadie que la ejercite.
  List<Widget> _formularioDeClave(ThemeData t) => [
        TextField(
          controller: _usuario,
          autofocus: !_conLlave,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Usuario',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _clave,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Clave',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _entrando ? null : _entrar(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_error!,
                style: t.textTheme.bodySmall
                    ?.copyWith(color: t.colorScheme.onErrorContainer)),
          ),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _entrando ? null : _entrar,
          child: Text(_entrando ? 'Entrando…' : 'Entrar'),
        ),
        const SizedBox(height: 8),
        Text('La semilla del núcleo trae usuario1 … usuario100, con clave '
            'admin123.', style: t.textTheme.bodySmall),
      ];

  /// El directorio: la lista de personas que vive en el núcleo.
  List<Widget> _bloqueDeDirectorio(ThemeData t) => [
        Row(
          children: [
            Expanded(
              child: Text(_conLlave ? '¿Con quién entrás?' : 'El directorio',
                  style: t.textTheme.titleMedium),
            ),
            if (_conLlave || Nucleo.token != null)
              IconButton(
                onPressed: _cargandoDirectorio ? null : _traerDirectorio,
                icon: const Icon(Icons.refresh),
                tooltip: 'Volver a traer',
              ),
          ],
        ),
        if (!_conLlave && Nucleo.token == null)
          Text('Se ve después de entrar: el núcleo lo protege con sesión, '
              'porque es la cartera del comercio.',
              style: t.textTheme.bodySmall)
        else ...[
          if (_conLlave)
            Text('Tocá un nombre y entrás como esa persona. Esta copia trae su '
                'propia llave de consulta, así que no hace falta la clave de nadie.',
                style: t.textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(
            controller: _busqueda,
            decoration: const InputDecoration(
              labelText: 'Buscar por nombre, cédula, ciudad o estado',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _traerDirectorio(),
          ),
          const SizedBox(height: 8),
          if (_cargandoDirectorio)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorDirectorio != null)
            // Nombra la ruta que falta en vez de romperse.
            Text(_errorDirectorio!,
                style: t.textTheme.bodySmall
                    ?.copyWith(color: t.colorScheme.error))
          else if (_directorio != null)
            ...[
              Text('${_directorio!.length} personas',
                  style: t.textTheme.bodySmall),
              for (final p in _directorio!)
                ListTile(
                  dense: true,
                  // Las empresas se marcan con RIF y los empleados con su
                  // organización: son los casos que hay que poder distinguir
                  // de un vistazo entre las cien.
                  title: Text(p.tipo == TipoDeSujeto.juridica
                      ? '${p.nombre} · RIF ${p.cedula}'
                      : p.organizacion != null
                          ? '${p.nombre} · ${p.organizacion!.nombre ?? p.organizacion!.codigo}'
                          : p.nombre),
                  subtitle: Text('identificador ${p.uuid}\n'
                      'cédula ${p.cedula} · ${p.estado} · usuario ${p.usuario}'),
                  trailing: _conLlave ? const Icon(Icons.login, size: 18) : null,
                  /*
                    🔴 CON LLAVE, TOCAR ENTRA — pedido de Juan, 2026-09-05:
                    «que no pida usuario y contraseña».

                    Antes tocar sólo completaba el usuario y había que escribir
                    `admin123` cien veces. Eso probaba el login del núcleo, sí, pero
                    el APK es para demostrar Collection —el permiso, el push, la
                    ubicación—, y la clave era un peaje antes de llegar a lo que se
                    va a mostrar. El login sigue abajo, plegado, para quien quiera
                    ejercer ese camino.
                  */
                  onTap: () {
                    if (_conLlave) {
                      Navigator.pop(context, p);
                      return;
                    }
                    _usuario.text = p.usuario;
                    FocusScope.of(context).unfocus();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Usuario ${p.usuario} · falta la clave')),
                    );
                  },
                ),
            ],
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (c, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(16),
        children: [
          Text('Entrar', style: t.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Las personas viven en el núcleo del comercio, no dentro de esta '
              'aplicación.\n$nucleoUrl',
              style: t.textTheme.bodySmall),
          const SizedBox(height: 16),

          // Con llave, el directorio va PRIMERO y es el camino normal.
          if (_conLlave) ...[
            ..._bloqueDeDirectorio(t),
            const Divider(height: 32),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Entrar con usuario y clave',
                  style: t.textTheme.titleMedium),
              subtitle: Text('El camino que usa una persona de verdad',
                  style: t.textTheme.bodySmall),
              children: [
                const SizedBox(height: 8),
                ..._formularioDeClave(t),
                const SizedBox(height: 8),
              ],
            ),
          ] else ...[
            ..._formularioDeClave(t),
            const Divider(height: 32),
            ..._bloqueDeDirectorio(t),
          ],
        ],
      ),
    );
  }
}

/// UNA LÍNEA QUE DICE SI LA LECTURA CONTINUA DE UBICACIÓN QUEDÓ ANDANDO.
///
/// Lo que importa que se lea es la diferencia entre lo que el comercio PIDIÓ y lo que está
/// corriendo. Si son distintos, el motivo va debajo: casi siempre es un permiso que la
/// aplicación tiene que declarar en su propio manifiesto y no declaró.
class _LineaDeUbicacion extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final pedido = AkPush.modoDeUbicacionPedido;
    final activo = AkPush.modoDeUbicacion;
    final anda = pedido == activo;
    final n = AkPush.lecturasDeUbicacionDeLaSesion;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (anda ? t.colorScheme.primary : t.colorScheme.error)
            .withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(anda ? Icons.my_location : Icons.location_disabled,
                size: 18,
                color: anda ? t.colorScheme.primary : t.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                anda
                    ? 'Ubicación · modo ${activo.name} · ${n.leidas} leídas / '
                        '${n.enviadas} enviadas'
                    : 'Ubicación · pidió ${pedido.name} y corre ${activo.name}',
                style: t.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: anda ? null : t.colorScheme.error,
                ),
              ),
            ),
          ]),
          if (!anda && AkPush.porQueNoHayLecturaContinua != null) ...[
            const SizedBox(height: 6),
            Text(AkPush.porQueNoHayLecturaContinua!,
                style: t.textTheme.bodySmall
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
