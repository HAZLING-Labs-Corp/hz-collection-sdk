/// EL MÓDULO DE COMPORTAMIENTO — qué hace la persona DENTRO de nuestra aplicación.
///
/// Ver la cabecera de `evento.dart` para el porqué del módulo y para el límite duro —el
/// contenido no se mide—. Acá está el cómo: quién escucha qué, cuándo se anota y cuándo sale.
///
/// ══ TRES COSAS QUE MIDE, Y NINGUNA PIDE UN PERMISO ══
///
///   · **La sesión.** Cuándo abre, cuándo cierra, cuánto duró, a qué hora del día. Sale del
///     ciclo de vida de Flutter, que es información de nuestra propia aplicación.
///   · **El formulario.** Cuándo lo abre, cuánto tarda en enviarlo, cuántas veces lo
///     abandona y vuelve. Lo declara quien integra con [ObservadorDeFormulario]: el SDK no
///     puede adivinar qué pantalla es «la solicitud».
///   · **Cómo llena los campos.** Si pega el dato o lo escribe, y cuántas veces lo corrige.
///     Sale de mirar el LARGO del texto cambiar, nunca el texto.
///
/// ══ 🔴 POR QUÉ ESTE MÓDULO NO PASA POR `RegistroDeModulos` ══
///
/// El registro sólo corre lo que el servidor declaró `activo`, y el catálogo del servicio
/// —`src/modulos/catalogo.ts`— tiene cinco entradas: avisos, ubicacion, senales,
/// autenticidad y rastreo. **No tiene `comportamiento`**, y agregarla es un cambio del back
/// que no me corresponde hacer esta noche. Enchufado al registro, este módulo sería código
/// muerto: nunca se activaría.
///
/// Así que se maneja desde la fachada, igual que `avisos`, y con la regla al revés que el
/// registro: **nace prendido y el servidor lo puede apagar**. Prender por omisión es
/// defendible acá y no lo sería en el registro, por una razón concreta: el registro apaga
/// por omisión para no pedirle a nadie un permiso que su comercio no pidió, y **este módulo
/// no pide ningún permiso ni lee nada de nadie más**. Y el encargo dice, textual, «acumula
/// desde el día uno»: un colector que espera una entrada de catálogo no acumula nada.
///
/// El día que el back agregue `comportamiento` al catálogo, esto lo obedece sin tocar una
/// línea: si la entrada existe y no dice `activo`, no corre.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../remote_config.dart';
import '../transmision/politica_de_transmision.dart';
import 'cola.dart';
import 'evento.dart';

/// Cómo está el módulo, para el diagnóstico y para poder mostrarlo en una pantalla.
class EstadoDelComportamiento {
  const EstadoDelComportamiento({
    required this.activo,
    required this.encolados,
    required this.descartadosSinAvisar,
    this.ultimoEnvio,
    this.salieronLaUltimaVez = 0,
    this.ultimoMotivo,
  });

  /// Si el módulo está midiendo. `false` cuando el servidor lo apagó.
  final bool activo;

  /// Cuántos eventos hay guardados esperando la próxima apertura.
  final int encolados;

  /// Cuántos se perdieron por desborde y todavía no se le contaron al servicio.
  final int descartadosSinAvisar;

  final DateTime? ultimoEnvio;
  final int salieronLaUltimaVez;

  /// Por qué no salieron, si no salieron. `null` cuando anda bien.
  final String? ultimoMotivo;

  @override
  String toString() => 'comportamiento: ${activo ? "midiendo" : "apagado"} · '
      '$encolados en cola'
      '${descartadosSinAvisar > 0 ? " · $descartadosSinAvisar descartados" : ""}'
      '${ultimoEnvio != null ? " · último envío: $salieronLaUltimaVez eventos" : " · todavía no envió"}'
      '${ultimoMotivo != null ? " · $ultimoMotivo" : ""}';
}

class Comportamiento with WidgetsBindingObserver {
  Comportamiento({this.politica = PoliticaDeTransmision.porOmision})
      : cola = ColaDeEventos(politica: politica);

  final PoliticaDeTransmision politica;
  final ColaDeEventos cola;

  static const _claveVueltas = 'akpush.comportamiento.vueltas';
  static const _claveFormAbierto = 'akpush.comportamiento.formularioAbierto';
  static const _claveSesion = 'akpush.comportamiento.sesionAbierta';

  AkPushApi? _api;
  String? _instalacionId;
  String? _sujetoId;
  bool _activo = true;
  bool _enganchado = false;

  DateTime? _sesionDesde;
  DateTime? _seFueAlFondo;

  DateTime? _ultimoEnvio;
  int _salieronLaUltimaVez = 0;
  String? _ultimoMotivo;

  /// 🔴 ARRANCA SIN TUMBAR NADA, PASE LO QUE PASE.
  ///
  /// Se la llama desde `init()`, que es la parte del arranque que la persona mira esperando.
  /// Todo lo de acá adentro está envuelto: si el almacenamiento falla, si el ciclo de vida
  /// no se puede enganchar, si la cola está corrupta, la aplicación abre igual y lo único
  /// que se pierde son unos eventos.
  Future<void> arrancar({
    required AkPushApi api,
    required String instalacionId,
    AkPushConfig? config,
    /// QUIÉN QUEDÓ LOGUEADO EN ESTE TELÉFONO LA VEZ PASADA.
    ///
    /// 🔴 No es una adivinanza: es el estado real de la instalación. El SDK guarda el
    /// usuario en el disco y lo borra al cerrar sesión, así que si hay uno, esa persona
    /// sigue adentro cuando la aplicación vuelve a abrir.
    ///
    /// Sin esto, **ningún `SESION_ABRE` llevaría sujeto nunca**: la aplicación abre antes de
    /// que nadie llame a `alIniciarSesion`, y el evento más importante de la serie —a qué
    /// hora abre esta persona— quedaría siempre colgado de la instalación y no de ella.
    String? sujetoConocido,
  }) async {
    try {
      _api = api;
      _instalacionId = instalacionId;
      _sujetoId ??= sujetoConocido;
      _activo = _loDejaElServidor(config);
      if (!_activo) return;

      if (!_enganchado) {
        WidgetsBinding.instance.addObserver(this);
        _enganchado = true;
      }

      // Primero se cierra lo que quedó colgado de la vez pasada, y en este orden: el
      // formulario abandonado pertenece a la sesión anterior, así que tiene que quedar en
      // la cola ANTES de su cierre, y los dos antes de la apertura de ahora.
      await _cerrarElFormularioQueQuedoAbierto();
      await _cerrarLaSesionQueQuedoAbierta();

      await _abrirSesion();
    } catch (_) {
      // A propósito, y es la promesa más importante del módulo: una medición perdida es un
      // problema; una aplicación que no abre es otro tamaño de problema.
    }
  }

  /// El servidor manda, pero sólo si dijo algo.
  ///
  /// Si la entrada `comportamiento` no existe en el catálogo —que es el caso hoy— el módulo
  /// corre. Si existe y no dice `activo`, no corre. Ver la nota grande de la cabecera.
  bool _loDejaElServidor(AkPushConfig? config) {
    final dicho = config?.modulos['comportamiento'];
    if (dicho == null) return true;
    return dicho.estado == 'activo';
  }

  /// Quién está adentro. Los eventos que se anoten desde ahora le pertenecen.
  void entroElSujeto(String sujetoId) => _sujetoId = sujetoId;

  /// Se fue. Lo que se anote desde ahora es de la instalación, no de nadie.
  void salioElSujeto() => _sujetoId = null;

  // ── El ciclo de vida: de acá salen SESION_ABRE y SESION_CIERRA ──────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_activo) return;
    // Nada de esto puede lanzar hacia el framework: el ciclo de vida lo llama Flutter, y
    // una excepción acá se ve como un error rojo en la pantalla de la persona.
    unawaited(() async {
      try {
        switch (state) {
          case AppLifecycleState.paused:
            await _seVaAlFondo();
          case AppLifecycleState.detached:
            // La aplicación se está muriendo de verdad: la sesión termina acá y ahora.
            await _cerrarSesion(DateTime.now());
          case AppLifecycleState.resumed:
            await _vuelve();
          default:
            // `inactive` y `hidden` pasan cada vez que baja la persiana de notificaciones
            // o entra una llamada. No son irse de la aplicación y no cierran nada.
            break;
        }
      } catch (_) {}
    }());
  }

  /// 🔴 IRSE AL FONDO NO CIERRA LA SESIÓN, Y ÉSTE ES EL ARREGLO QUE MÁS IMPORTA DE ACÁ.
  ///
  /// Al principio esto emitía `SESION_CIERRA` en cada `paused`. Medido en el emulador el
  /// 2026-09-04: **dos cierres para una sola apertura**, porque mirar la hora manda la
  /// aplicación al fondo y la trae de vuelta en cuatro segundos. Y el segundo cierre medía
  /// desde la pausa anterior, así que «cuánto duró la sesión» era un número inventado.
  ///
  /// Ahora sólo se anota HASTA CUÁNDO se la vio. Si vuelve dentro de la ventana, la sesión
  /// sigue y nadie se entera; si vuelve después, o si la aplicación murió, ahí se cierra —
  /// con este momento y no con el de la vuelta, que es cuando de verdad dejó de usarla.
  Future<void> _seVaAlFondo() async {
    _seFueAlFondo = DateTime.now();
    await _guardarLaSesionAbierta();
    // Si había un formulario abierto, la misma marca sirve para cerrarlo si no vuelve.
    await _marcarQueSeFue();
  }

  /// Una vuelta a la aplicación NO siempre es una sesión nueva.
  ///
  /// Mirar la hora en medio de llenar un formulario manda la app al fondo y la trae de
  /// vuelta en cuatro segundos. Contar dos sesiones ahí inventa un patrón de uso que no
  /// existe, y encima parte el tiempo de llenado en dos. Sólo cuenta como sesión nueva
  /// después de [PoliticaDeTransmision.sesionMuertaTrasMinutos] de silencio.
  Future<void> _vuelve() async {
    final seFue = _seFueAlFondo;
    _seFueAlFondo = null;
    if (seFue == null) return;
    if (DateTime.now().difference(seFue).inMinutes <
        politica.sesionMuertaTrasMinutos) {
      return; // la misma sesión sigue: no se anota nada
    }
    // Estuvo callada más de la cuenta: la sesión anterior terminó cuando se fue, no ahora.
    await _cerrarSesion(seFue);
    await _abrirSesion();
  }

  Future<void> _abrirSesion() async {
    // Una segunda llamada a `init()` —un reinicio en caliente, una integración que la llama
    // dos veces— no puede abrir una segunda sesión encima de la que está abierta: serían dos
    // aperturas y un solo cierre, y la serie mostraría sesiones que nadie tuvo.
    if (_sesionDesde != null) return;

    final ahora = DateTime.now();
    _sesionDesde = ahora;
    await _guardarLaSesionAbierta();

    // 🔴 LA HORA LOCAL VIAJA EN `datos` Y NO SE DEDUCE DE `cuando`.
    //
    // `cuando` va en UTC, como todo lo demás del SDK. Del otro lado, «abrió a las 3 de la
    // madrugada» —que es una de las señales que más dice de alguien— no se puede
    // reconstruir de un UTC sin saber en qué huso está el teléfono. Va acá, medida donde
    // se sabe.
    final descartados = await cola.tomarDescartados();
    await _anotar(
      TipoDeEvento.sesionAbre,
      datos: {
        'hora_local': ahora.hour,
        'dia_de_semana': ahora.weekday,
        'desfase_min': ahora.timeZoneOffset.inMinutes,
        // Cuántos eventos se perdieron por desborde desde el último aviso. Que el hueco se
        // pueda ver del otro lado es lo que separa «no hizo nada» de «no lo pudimos guardar».
        if (descartados > 0) 'eventos_descartados': descartados,
      },
    );
  }

  /// Cierra la sesión abierta. [hasta] es cuándo se dejó de usar la aplicación, que **no**
  /// es cuándo nos enteramos: si la persona se fue al fondo y volvió cuarenta minutos
  /// después, la sesión terminó cuando se fue.
  Future<void> _cerrarSesion(DateTime hasta, {bool murioLaApp = false}) async {
    final desde = _sesionDesde;
    _sesionDesde = null;
    await _olvidarLaSesionAbierta();
    if (desde == null) return;
    await _anotar(
      TipoDeEvento.sesionCierra,
      cuando: hasta,
      ms: hasta.difference(desde).inMilliseconds,
      // Para que del otro lado se sepa que este cierre se dedujo en el arranque siguiente y
      // no se observó. Sin la marca, una sesión reconstruida se lee como una medida directa.
      datos: murioLaApp ? const {'cerro_la_app': true} : const {},
    );
  }

  /// LA SESIÓN ABIERTA, EN EL DISCO — para poder cerrarla si la aplicación no vuelve.
  ///
  /// 🔴 Sin esto se pierde el evento más caro de todos. Android mata las aplicaciones que
  /// están en el fondo sin avisarle a nadie: no hay `detached`, no hay último suspiro, y la
  /// sesión más larga —la que terminó porque el sistema necesitaba memoria— quedaría sin
  /// cerrar para siempre. Se anota cuándo empezó y hasta cuándo se la vio, y el arranque
  /// siguiente la cierra con esos dos números.
  Future<void> _guardarLaSesionAbierta() async {
    final desde = _sesionDesde;
    if (desde == null) return;
    try {
      await (await SharedPreferences.getInstance()).setStringList(
        _claveSesion,
        [desde.toIso8601String(), DateTime.now().toIso8601String()],
      );
    } catch (_) {}
  }

  Future<void> _olvidarLaSesionAbierta() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_claveSesion);
    } catch (_) {}
  }

  /// La sesión que quedó abierta cuando la aplicación murió. Se cierra en el arranque
  /// siguiente, con el último momento en que se la vio.
  Future<void> _cerrarLaSesionQueQuedoAbierta() async {
    // 🔴 Si ya hay una sesión abierta EN MEMORIA, el registro del disco es de esta misma
    // corrida y no es un sobrante de nadie. Sin esta línea, un segundo `init()` —un
    // reinicio en caliente— cerraría la sesión que acaba de abrir y abriría otra: dos
    // aperturas y un cierre para una sola vez que la persona abrió la aplicación.
    if (_sesionDesde != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final r = prefs.getStringList(_claveSesion);
      if (r == null || r.length < 2) return;
      final desde = DateTime.tryParse(r[0]);
      final hasta = DateTime.tryParse(r[1]);
      await prefs.remove(_claveSesion);
      if (desde == null || hasta == null) return;
      _sesionDesde = desde;
      await _cerrarSesion(hasta, murioLaApp: true);
    } catch (_) {}
  }

  // ── El formulario ───────────────────────────────────────────────────────────────

  /// Empieza a mirar un formulario. El nombre lo pone quien integra: `solicitud`,
  /// `datos_del_aval`. Es un rótulo de la aplicación, no algo que haya escrito nadie.
  ///
  /// 🔴 EL MISMO NOMBRE DEVUELVE EL MISMO OBSERVADOR, y eso evita un fallo caro. Cada
  /// observador es dueño de los `TextEditingController` de sus campos; si esto creara uno
  /// nuevo en cada llamada, alguien que lo pida desde `build()` —que es donde uno pide las
  /// cosas en Flutter— tendría controladores nuevos en cada cuadro y **el texto que la
  /// persona escribió desaparecería mientras escribe**. Al soltarlo con `dispose()` se
  /// olvida, así que volver a la pantalla arranca uno limpio.
  ObservadorDeFormulario formulario(String nombre) =>
      _formularios.putIfAbsent(nombre, () => ObservadorDeFormulario._(this, nombre));

  final Map<String, ObservadorDeFormulario> _formularios = {};

  Future<int> _proximaVuelta(String formulario) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final crudo = prefs.getStringList(_claveVueltas) ?? const <String>[];
      final mapa = <String, int>{};
      for (final l in crudo) {
        final i = l.indexOf('=');
        if (i > 0) mapa[l.substring(0, i)] = int.tryParse(l.substring(i + 1)) ?? 0;
      }
      final n = (mapa[formulario] ?? 0) + 1;
      mapa[formulario] = n;
      await prefs.setStringList(
          _claveVueltas, mapa.entries.map((e) => '${e.key}=${e.value}').toList());
      return n;
    } catch (_) {
      return 1;
    }
  }

  Future<void> _guardarQueHayUnoAbierto(String nombre, DateTime desde, int vuelta) async {
    try {
      await (await SharedPreferences.getInstance()).setStringList(
        _claveFormAbierto,
        [nombre, desde.toIso8601String(), '$vuelta', ''],
      );
    } catch (_) {}
  }

  Future<void> _marcarQueSeFue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final r = prefs.getStringList(_claveFormAbierto);
      if (r == null || r.length < 4) return;
      await prefs.setStringList(
          _claveFormAbierto, [r[0], r[1], r[2], DateTime.now().toIso8601String()]);
    } catch (_) {}
  }

  Future<void> _olvidarElAbierto() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_claveFormAbierto);
    } catch (_) {}
  }

  /// El abandono que nadie declara: la persona cerró la aplicación con el formulario
  /// abierto. Se descubre en el arranque siguiente.
  Future<void> _cerrarElFormularioQueQuedoAbierto() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final r = prefs.getStringList(_claveFormAbierto);
      if (r == null || r.length < 4) return;
      await prefs.remove(_claveFormAbierto);
      final desde = DateTime.tryParse(r[1]);
      final hasta = r[3].isEmpty ? null : DateTime.tryParse(r[3]);
      await _anotar(
        TipoDeEvento.formularioAbandona,
        // Si no se alcanzó a anotar cuándo se fue —la aplicación murió sin avisar— no se
        // inventa un número: viaja sin `ms`. Un tiempo de llenado inventado es peor que
        // ninguno, porque nadie puede distinguirlo del medido.
        ms: (desde != null && hasta != null)
            ? hasta.difference(desde).inMilliseconds
            : null,
        datos: {
          'formulario': r[0],
          'vuelta': int.tryParse(r[2]) ?? 0,
          // Para que del otro lado se sepa que este abandono se dedujo, no se observó.
          'cerro_la_app': true,
        },
        cuando: hasta,
      );
    } catch (_) {}
  }

  // ── Anotar y transmitir ─────────────────────────────────────────────────────────

  Future<void> _anotar(
    String tipo, {
    int? ms,
    Map<String, Object?> datos = const {},
    DateTime? cuando,
  }) async {
    if (!_activo) return;
    try {
      await cola.encolar(EventoDeComportamiento(
        tipo: tipo,
        cuando: cuando ?? DateTime.now(),
        seq: await cola.proximoSeq(),
        ms: ms,
        datos: datos,
        sujetoId: _sujetoId,
      ));
    } catch (_) {}
  }

  /// MANDA LO QUE HAY, POR LOTE. Devuelve cuántos eventos salieron.
  ///
  /// 🔴 Se la llama UNA vez por apertura de la aplicación, y no en cada medición. Ésa es
  /// toda la política: lo que se mide se guarda, y lo guardado sale junto la próxima vez
  /// que la persona abra.
  ///
  /// Nunca lanza. Si no hay red, los eventos se quedan donde estaban y se reintenta en la
  /// próxima apertura — que es exactamente para lo que la cola vive en el disco.
  Future<int> transmitir() async {
    final api = _api;
    final instalacion = _instalacionId;
    if (!_activo || api == null || instalacion == null) return 0;

    var salieron = 0;
    try {
      final todos = await cola.leer();
      if (todos.isEmpty) {
        _ultimoMotivo = null;
        return 0;
      }

      for (final lote in _armarLotes(todos)) {
        await api.reportarComportamiento(
          instalacionId: instalacion,
          sujetoId: lote.first.sujetoId,
          eventos: lote.map((e) => e.aContrato()).toList(),
        );
        // Se borra DESPUÉS de que el servicio aceptó, y sólo lo que iba en este lote: entre
        // que sale la petición y vuelve la respuesta, la persona pudo tocar un campo, y un
        // borrado por rango se llevaría ese evento sin haberlo mandado nunca.
        await cola.quitarLos(lote.map((e) => e.seq).toSet());
        salieron += lote.length;
      }
      _ultimoEnvio = DateTime.now();
      _salieronLaUltimaVez = salieron;
      _ultimoMotivo = null;
    } catch (e) {
      // Se queda todo en la cola. No es un fallo del que llama: es que no hay red, y la
      // cola existe justamente para eso.
      _ultimoMotivo = 'no se pudo enviar: $e';
    }
    return salieron;
  }

  /// Parte la cola en lotes, y no por capricho.
  ///
  /// Por **sujeto**, porque una cola sin red puede cruzar un cierre de sesión y contener
  /// eventos de dos personas; el lote lleva el sujeto en el sobre, así que uno solo no
  /// alcanza. Y por **tamaño**, porque después de dos semanas sin red la cola puede tener
  /// mil eventos: un cuerpo de 120 KB en una red de datos venezolana es una petición que
  /// falla, y falla entera. En lotes, lo que llegó queda del otro lado.
  Iterable<List<EventoDeComportamiento>> _armarLotes(
      List<EventoDeComportamiento> todos) sync* {
    var actual = <EventoDeComportamiento>[];
    for (final e in todos) {
      final cambioDeSujeto = actual.isNotEmpty && actual.first.sujetoId != e.sujetoId;
      if (cambioDeSujeto || actual.length >= politica.topeDeLote) {
        yield actual;
        actual = <EventoDeComportamiento>[];
      }
      actual.add(e);
    }
    if (actual.isNotEmpty) yield actual;
  }

  Future<EstadoDelComportamiento> estado() async => EstadoDelComportamiento(
        activo: _activo,
        encolados: await cola.cuantos(),
        descartadosSinAvisar: await cola.cuantosDescartados(),
        ultimoEnvio: _ultimoEnvio,
        salieronLaUltimaVez: _salieronLaUltimaVez,
        ultimoMotivo: _ultimoMotivo,
      );

  /// Suelta el gancho del ciclo de vida. Para las pruebas y para un cierre ordenado.
  void soltar() {
    if (!_enganchado) return;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _enganchado = false;
  }
}

/// UN FORMULARIO MIRADO — cuánto tarda en llenarlo, y cuántas veces lo deja.
///
/// Quien integra escribe tres líneas:
///
/// ```dart
/// final f = AkPush.formulario('solicitud');   // en initState
/// await f.abrir();
/// ...
/// TextField(controller: f.campo('cedula').controlador,
///           focusNode:  f.campo('cedula').foco)
/// ...
/// await f.enviar();                            // al apretar Enviar
/// f.dispose();                                 // en dispose
/// ```
///
/// El SDK no puede adivinar qué pantalla es «la solicitud» ni cuál de los botones la envía.
/// Por eso esto se declara y no se detecta solo — y por eso el nombre del formulario y el
/// del campo son rótulos que pone la aplicación, no texto de nadie.
class ObservadorDeFormulario {
  ObservadorDeFormulario._(this._motor, this.nombre);

  final Comportamiento _motor;
  final String nombre;

  final Map<String, ObservadorDeCampo> _campos = {};
  DateTime? _desde;
  int _vuelta = 0;
  bool _cerrado = false;

  /// La persona entró al formulario. `vuelta` cuenta cuántas veces lo abrió en la vida de
  /// esta instalación: la segunda vuelta después de un abandono es una señal por sí sola.
  Future<void> abrir() async {
    if (_desde != null) return; // ya estaba abierto: no se cuenta dos veces
    _desde = DateTime.now();
    _cerrado = false;
    _vuelta = await _motor._proximaVuelta(nombre);
    await _motor._guardarQueHayUnoAbierto(nombre, _desde!, _vuelta);
    await _motor._anotar(
      TipoDeEvento.formularioAbre,
      datos: {'formulario': nombre, 'vuelta': _vuelta},
    );
  }

  /// Lo envió. `ms` es el tiempo de llenado, que es la medida que se pidió.
  Future<void> enviar() => _cerrar(TipoDeEvento.formularioEnvia);

  /// Se fue sin enviarlo.
  Future<void> abandonar() => _cerrar(TipoDeEvento.formularioAbandona);

  Future<void> _cerrar(String tipo) async {
    if (_cerrado || _desde == null) return;
    _cerrado = true;
    // Primero los campos, para que en la cola queden ANTES del cierre del formulario: un
    // campo que se emite después de «enviado» se lee como si lo hubieran tocado después.
    for (final c in _campos.values) {
      await c._emitirSiHayAlgo();
    }
    await _motor._olvidarElAbierto();
    await _motor._anotar(
      tipo,
      ms: DateTime.now().difference(_desde!).inMilliseconds,
      datos: {'formulario': nombre, 'vuelta': _vuelta},
    );
    _desde = null;
  }

  /// El observador de un campo. Se pide una vez por campo y se reusa: pedirlo dos veces
  /// devuelve el mismo, así que se puede llamar desde `build` sin perder la cuenta.
  ObservadorDeCampo campo(String nombre) =>
      _campos.putIfAbsent(nombre, () => ObservadorDeCampo._(this, nombre));

  /// Se llama desde el `dispose` de la pantalla. Si el formulario no se envió, esto es un
  /// abandono — que es como se abandona un formulario de verdad: yéndose de la pantalla.
  void dispose() {
    unawaited(_cerrar(TipoDeEvento.formularioAbandona));
    for (final c in _campos.values) {
      c._soltar();
    }
    // El motor lo suelta: la próxima vez que alguien entre a esta pantalla va a pedir uno
    // nuevo, y devolverle éste —con los controladores ya liberados— reventaría al primer
    // `TextField` que lo use.
    _motor._formularios.remove(nombre);
  }
}

/// UN CAMPO MIRADO — si lo pegó o lo escribió, y cuántas veces lo corrigió.
///
/// ══ 🔴 CÓMO SE SABE QUE PEGÓ SIN LEER LO QUE PEGÓ ══
///
/// Mirando el LARGO del texto, nada más. Escribir agrega un carácter por vez; pegar agrega
/// todos de golpe. Un solo cambio que suma [_minimoDePegado] caracteres o más es un pegado,
/// y también lo es llenar un campo vacío de una sola vez.
///
/// **Su límite, dicho antes de que alguien lo descubra midiendo:** en un campo de texto
/// libre con sugerencias del teclado, tocar una sugerencia inserta una palabra entera y se
/// ve igual que un pegado. En los campos donde esto importa —cédula, monto, teléfono— el
/// teclado es numérico y no hay sugerencias, así que ahí no se confunde. Para un campo de
/// nombre y apellido, la señal es más floja y hay que leerla como tal.
///
/// ══ LO QUE NO SE MIRA, Y ES A PROPÓSITO ══
///
/// El texto, ni entero ni en pedazos. Su largo tampoco: se consideró —distinguiría pegar
/// ocho dígitos de pegar doscientos— y se descartó, porque no hace falta para nada de lo que
/// hay que contestar y es lo único de la lista que se parece al contenido. Lo que se cuenta
/// son las **correcciones**: cuántas veces el texto se acortó, que es un número de acciones.
class ObservadorDeCampo {
  ObservadorDeCampo._(this._formulario, this.campo) {
    controlador.addListener(_alCambiar);
    foco.addListener(_alCambiarElFoco);
  }

  final ObservadorDeFormulario _formulario;
  final String campo;

  /// El controlador YA observado. La aplicación se lo pasa a su `TextField` y no escribe
  /// una línea más. Se puede leer `controlador.text` como cualquier otro.
  final TextEditingController controlador = TextEditingController();

  /// El foco, para saber cuándo entró y cuándo salió del campo — que es lo que delimita
  /// «cuánto tardó en llenarlo».
  final FocusNode foco = FocusNode();

  /// Cuatro caracteres de un golpe. Debajo de eso hay demasiado teclado predictivo; encima,
  /// casi nada que no sea un pegado. Los datos que importan acá —una cédula, un teléfono,
  /// un monto— tienen todos más de cuatro.
  static const _minimoDePegado = 4;

  int _largoAnterior = 0;
  bool _pego = false;
  int _correcciones = 0;
  bool _huboCambios = false;
  DateTime? _entro;

  void _alCambiar() {
    final largo = controlador.text.length;
    final delta = largo - _largoAnterior;
    if (delta != 0) _huboCambios = true;

    // Un golpe grande, o un campo vacío que se llena entero de una vez.
    if (delta >= _minimoDePegado || (_largoAnterior == 0 && delta >= 2 && delta == largo)) {
      _pego = true;
    }
    // El texto se acortó: borró. Es lo que se cuenta como corrección — el número de veces
    // que tuvo que volver atrás, no cuánto borró.
    if (delta < 0) _correcciones++;

    _largoAnterior = largo;
    _entro ??= DateTime.now();
  }

  void _alCambiarElFoco() {
    if (foco.hasFocus) {
      _entro ??= DateTime.now();
    } else {
      unawaited(_emitirSiHayAlgo());
    }
  }

  /// Emite el evento del campo si pasó algo que valga la pena. Idempotente por ronda: si
  /// la persona vuelve al campo y lo edita otra vez, eso es otro evento y está bien que lo
  /// sea — dos pasadas por el mismo campo es información.
  Future<void> _emitirSiHayAlgo() async {
    if (!_huboCambios) return; // entró y salió sin tocar nada: no es un evento
    final desde = _entro;
    _huboCambios = false;
    _entro = null;
    final pego = _pego;
    final correcciones = _correcciones;
    _pego = false;
    _correcciones = 0;

    await _formulario._motor._anotar(
      pego ? TipoDeEvento.campoPegado : TipoDeEvento.campoEscrito,
      ms: desde == null ? null : DateTime.now().difference(desde).inMilliseconds,
      datos: {
        'formulario': _formulario.nombre,
        'campo': campo,
        'correcciones': correcciones,
      },
    );
  }

  void _soltar() {
    controlador.removeListener(_alCambiar);
    foco.removeListener(_alCambiarElFoco);
    controlador.dispose();
    foco.dispose();
  }
}
