/// EL COMPORTAMIENTO DENTRO DE LA PROPIA APLICACIÓN.
///
/// Tres cosas se prueban acá, y la primera es la que no se puede negociar:
///
///  1. **Que el contenido no sale.** Se escribe y se pega una cédula de verdad y se
///     comprueba que ni un carácter de ella aparece en nada de lo que el SDK guardaría o
///     mandaría. Es un límite duro y una promesa que hay que poder demostrar, no afirmar.
///  2. **Que los siete tipos son los del contrato.** Hay un back construyéndose contra esos
///     nombres; un octavo nombre inventado acá se descarta del otro lado sin decir nada.
///  3. **Que la cola aguanta sin red.** Tope, descarte del más viejo, y que lo que se borra
///     es exactamente lo que salió.
library;

import 'dart:convert';

import 'package:flutter/widgets.dart' show AppLifecycleState;

import 'package:flutter_test/flutter_test.dart';
import 'package:hz_collection_sdk/src/api_client.dart';
import 'package:hz_collection_sdk/src/comportamiento/cola.dart';
import 'package:hz_collection_sdk/src/comportamiento/comportamiento.dart';
import 'package:hz_collection_sdk/src/comportamiento/evento.dart';
import 'package:hz_collection_sdk/src/transmision/politica_de_transmision.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EventoDeComportamiento evento(int seq, {String? sujeto, String tipo = TipoDeEvento.sesionAbre}) =>
      EventoDeComportamiento(
        tipo: tipo,
        cuando: DateTime(2026, 9, 4, 22, 0, seq % 60),
        seq: seq,
        sujetoId: sujeto,
      );

  group('los tipos del contrato', () {
    test('son exactamente los siete, con los nombres del contrato', () {
      // 🔴 Si alguien renombra uno, el back —que se construyó contra estos siete la misma
      // noche— descarta ese evento en silencio. Es un fallo sin síntoma: el teléfono manda,
      // el servidor contesta 200, y la serie sale sin ese tipo de evento y nadie lo nota.
      expect(TipoDeEvento.todos, [
        'SESION_ABRE',
        'SESION_CIERRA',
        'FORMULARIO_ABRE',
        'FORMULARIO_ENVIA',
        'FORMULARIO_ABANDONA',
        'CAMPO_PEGADO',
        'CAMPO_ESCRITO',
      ]);
    });

    test('lo que viaja tiene la forma del contrato y nada más', () {
      final j = EventoDeComportamiento(
        tipo: TipoDeEvento.formularioEnvia,
        cuando: DateTime.utc(2026, 9, 4, 22, 15),
        seq: 41,
        ms: 38400,
        datos: const {'formulario': 'solicitud', 'vuelta': 2},
      ).aContrato();

      expect(j.keys.toSet(), {'tipo', 'cuando', 'ms', 'datos'});
      expect(j['cuando'], '2026-09-04T22:15:00.000Z');
      // `seq` viaja adentro de `datos`, que es un mapa abierto, y no como un quinto campo:
      // agregar un campo al lado de los cuatro sería cambiar el contrato por mi cuenta.
      expect((j['datos'] as Map)['seq'], 41);
    });

    test('un evento guardado se vuelve a leer igual, y uno ilegible no rompe la cola', () {
      final e = evento(7, sujeto: 'u_1');
      final vuelto = EventoDeComportamiento.deDisco(jsonDecode(jsonEncode(e.aDisco())));
      expect(vuelto!.tipo, e.tipo);
      expect(vuelto.seq, 7);
      expect(vuelto.sujetoId, 'u_1');

      // Perder cien eventos buenos por uno malo —y en el arranque de la aplicación— no.
      expect(EventoDeComportamiento.deDisco({'lo que sea': 1}), isNull);
      expect(EventoDeComportamiento.deDisco('una cadena'), isNull);
    });
  });

  group('la cola sin red', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('guarda, lee en orden, y borra sólo lo que salió', () async {
      final cola = ColaDeEventos();
      for (var i = 1; i <= 5; i++) {
        await cola.encolar(evento(i));
      }
      expect((await cola.leer()).map((e) => e.seq), [1, 2, 3, 4, 5]);

      // Salieron el 1, el 2 y el 4 —porque los lotes se parten por sujeto y no son un
      // rango contiguo—. Tienen que quedar exactamente el 3 y el 5.
      await cola.quitarLos({1, 2, 4});
      expect((await cola.leer()).map((e) => e.seq), [3, 5]);
    });

    test('🔴 al llenarse descarta el MÁS VIEJO y lo cuenta', () async {
      // Descartar lo nuevo congelaría la cola de un teléfono sin red: la serie mostraría a
      // alguien que dejó de usar la aplicación el día que se quedó sin señal, que es
      // activamente falso y no meramente incompleto.
      final cola = ColaDeEventos(politica: const PoliticaDeTransmision(topeDeEventos: 3));
      for (var i = 1; i <= 6; i++) {
        await cola.encolar(evento(i));
      }
      expect((await cola.leer()).map((e) => e.seq), [4, 5, 6]);
      expect(await cola.cuantosDescartados(), 3);

      // Se consume una sola vez: viaja en el `datos` del siguiente SESION_ABRE y no se
      // repite en el de después, que haría contar el mismo hueco dos veces.
      expect(await cola.tomarDescartados(), 3);
      expect(await cola.tomarDescartados(), 0);
    });

    test('el tope de bytes corta antes que el de eventos cuando los eventos pesan', () async {
      final cola = ColaDeEventos(
          politica: const PoliticaDeTransmision(topeDeEventos: 1000, topeDeBytes: 400));
      for (var i = 1; i <= 20; i++) {
        await cola.encolar(evento(i));
      }
      final quedan = await cola.leer();
      expect(quedan.length, lessThan(20));
      expect(quedan.last.seq, 20, reason: 'lo último es lo que se conserva');
      expect(await cola.cuantosDescartados(), greaterThan(0));
    });

    test('los números de secuencia sólo crecen y sobreviven al arranque', () async {
      final cola = ColaDeEventos();
      final a = await cola.proximoSeq();
      final b = await cola.proximoSeq();
      expect(b, a + 1);
      // Otra instancia —otro arranque de la aplicación— sigue donde quedó.
      expect(await ColaDeEventos().proximoSeq(), b + 1);
    });
  });

  group('🔴 el contenido de lo que escribe la persona NO se captura', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    /// Una cédula del juego de prueba. Se usa a propósito una que parezca de verdad: la
    /// prueba tiene que fallar si alguien deja escapar un dato real, no uno de juguete.
    const cedula = '17229393';

    test('escribir la cédula letra por letra no deja ni un carácter en ningún evento',
        () async {
      final motor = Comportamiento();
      await motor.arrancar(
          api: _apiQueNoSeUsa(), instalacionId: 'i_1', config: null);
      final f = motor.formulario('solicitud');
      await f.abrir();

      final campo = f.campo('cedula');
      for (var i = 1; i <= cedula.length; i++) {
        campo.controlador.text = cedula.substring(0, i);
      }
      // Se equivoca y borra dos veces: eso es lo único que se cuenta del contenido.
      campo.controlador.text = cedula.substring(0, cedula.length - 1);
      campo.controlador.text = cedula;
      await f.enviar();

      final eventos = await motor.cola.leer();
      final todo = jsonEncode(eventos.map((e) => e.aContrato()).toList());

      // ── 1. La cédula entera no está en NINGÚN lado del lote ────────────────────────
      // Ocho dígitos seguidos no aparecen por casualidad.
      expect(todo, isNot(contains(cedula)));

      // ── 2. 🔴 LA LISTA DE CLAVES ES CERRADA — es la prueba que de verdad protege ────
      //
      // Buscar pedazos del contenido dentro del JSON parece más severo y es peor: `22` de
      // la cédula aparece dentro de `hora_local: 22`, y `393` dentro de una marca de tiempo
      // en microsegundos. La primera versión de esta prueba fallaba una vez cada tres
      // corridas por eso, y una prueba que grita sin motivo se termina ignorando — justo
      // el día que haya una fuga de verdad.
      //
      // Lo que sí se puede afirmar sin ambigüedad es **qué claves viajan**. Si mañana
      // alguien agrega `largo`, o `texto`, o `hash`, esto falla y hay que venir a
      // discutirlo acá, que es exactamente donde está escrito por qué no van.
      const clavesPermitidas = {
        'seq',            // el número de la cola, para borrar y para descartar repetidos
        'hora_local',     // 0-23 — lo que el UTC no puede reconstruir del otro lado
        'dia_de_semana',  // 1-7
        'desfase_min',    // el huso, para poder reconstruir la hora local de los demás
        'eventos_descartados',
        'formulario',     // un rótulo que pone quien integra
        'campo',          // idem
        'vuelta',         // cuántas veces abrió este formulario
        'correcciones',   // cuántas veces borró — un número de acciones, no del dato
        'cerro_la_app',
      };
      for (final e in eventos) {
        expect(e.datos.keys.toSet().difference(clavesPermitidas), isEmpty,
            reason: 'apareció una clave nueva en ${e.tipo}: hay que justificarla acá');
      }

      // ── 3. Ningún valor de TEXTO es otra cosa que un rótulo del formulario ─────────
      // Los números son contadores y duraciones que genera el SDK; el único lugar donde
      // podría esconderse algo que escribió la persona es una cadena.
      const rotulosDeclarados = {'solicitud', 'cedula', 'telefono', 'monto', 'motivo'};
      for (final e in eventos) {
        for (final v in e.datos.values) {
          if (v is String) {
            expect(rotulosDeclarados, contains(v),
                reason: 'viajó un texto que no es un rótulo declarado: «$v»');
          }
        }
      }

      final delCampo =
          eventos.firstWhere((e) => e.tipo.startsWith('CAMPO_'));
      expect(delCampo.tipo, TipoDeEvento.campoEscrito, reason: 'lo escribió, no lo pegó');
      expect(delCampo.datos['campo'], 'cedula');
      expect(delCampo.datos['correcciones'], 1);
      // Y no está el largo. Se consideró y se descartó: no hace falta para nada de lo que
      // hay que contestar, y es lo único de la lista que se parece al contenido.
      expect(delCampo.datos.containsKey('largo'), isFalse);

      motor.soltar();
    });

    test('pegarla de un golpe se distingue de escribirla, y tampoco deja rastro del dato',
        () async {
      final motor = Comportamiento();
      await motor.arrancar(
          api: _apiQueNoSeUsa(), instalacionId: 'i_1', config: null);
      final f = motor.formulario('solicitud');
      await f.abrir();

      final campo = f.campo('cedula');
      campo.controlador.text = cedula; // de un solo golpe: es lo que hace un pegado
      await f.enviar();

      final eventos = await motor.cola.leer();
      final delCampo = eventos.firstWhere((e) => e.tipo.startsWith('CAMPO_'));
      expect(delCampo.tipo, TipoDeEvento.campoPegado);
      expect(jsonEncode(delCampo.aContrato()), isNot(contains(cedula)));

      motor.soltar();
    });
  });

  group('la sesión y el formulario', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('al arrancar anota SESION_ABRE con la hora local, que el UTC no puede reconstruir',
        () async {
      final motor = Comportamiento();
      await motor.arrancar(api: _apiQueNoSeUsa(), instalacionId: 'i_1', config: null);
      final e = (await motor.cola.leer()).single;
      expect(e.tipo, TipoDeEvento.sesionAbre);
      expect(e.datos['hora_local'], DateTime.now().hour);
      expect(e.datos['dia_de_semana'], DateTime.now().weekday);
      expect(e.datos['desfase_min'], DateTime.now().timeZoneOffset.inMinutes);
      motor.soltar();
    });

    test('el formulario cuenta las vueltas, y la segunda es una señal por sí sola', () async {
      final motor = Comportamiento();
      await motor.arrancar(api: _apiQueNoSeUsa(), instalacionId: 'i_1', config: null);

      final primera = motor.formulario('solicitud');
      await primera.abrir();
      await primera.abandonar();

      final segunda = motor.formulario('solicitud');
      await segunda.abrir();
      await segunda.enviar();

      final eventos = await motor.cola.leer();
      final abre = eventos.where((e) => e.tipo == TipoDeEvento.formularioAbre).toList();
      expect(abre.map((e) => e.datos['vuelta']), [1, 2]);
      expect(eventos.any((e) => e.tipo == TipoDeEvento.formularioAbandona), isTrue);
      final envia = eventos.firstWhere((e) => e.tipo == TipoDeEvento.formularioEnvia);
      expect(envia.ms, isNotNull, reason: 'el tiempo de llenado es lo que se pidió medir');
      motor.soltar();
    });

    test('el abandono más común —cerrar la app con el formulario abierto— se descubre solo',
        () async {
      final unMotor = Comportamiento();
      await unMotor.arrancar(api: _apiQueNoSeUsa(), instalacionId: 'i_1', config: null);
      await unMotor.formulario('solicitud').abrir();
      unMotor.soltar();
      // La aplicación se muere acá: nadie llama a `abandonar()`, y sin embargo el
      // formulario quedó abandonado. Es como se abandona un formulario de verdad.

      final otroArranque = Comportamiento();
      await otroArranque.arrancar(
          api: _apiQueNoSeUsa(), instalacionId: 'i_1', config: null);
      final eventos = await otroArranque.cola.leer();
      final abandono =
          eventos.firstWhere((e) => e.tipo == TipoDeEvento.formularioAbandona);
      expect(abandono.datos['formulario'], 'solicitud');
      expect(abandono.datos['cerro_la_app'], isTrue,
          reason: 'del otro lado hay que saber que este abandono se dedujo, no se observó');
      otroArranque.soltar();
    });

    test('🔴 una apertura da UN cierre, no dos — irse al fondo no cierra la sesión', () async {
      // Al principio esto emitía SESION_CIERRA en cada `paused`, y medido en el emulador
      // salían dos cierres para una sola apertura: mirar la hora manda la app al fondo y la
      // trae en cuatro segundos. Peor todavía, el segundo cierre medía desde la pausa
      // anterior, así que «cuánto duró» era un número inventado.
      final motor = Comportamiento();
      await motor.arrancar(api: _apiQueNoSeUsa(), instalacionId: 'i_1', config: null);

      motor.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      motor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      motor.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      motor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final eventos = await motor.cola.leer();
      expect(eventos.where((e) => e.tipo == TipoDeEvento.sesionAbre).length, 1);
      expect(eventos.where((e) => e.tipo == TipoDeEvento.sesionCierra).length, 0,
          reason: 'volvió enseguida las dos veces: la sesión nunca terminó');
      motor.soltar();
    });

    test('la app que muere en el fondo deja su cierre para el arranque siguiente', () async {
      // Android mata las aplicaciones del fondo sin avisar: no hay `detached` ni último
      // suspiro. Sin esto, la sesión más larga —la que terminó porque el sistema necesitaba
      // memoria— quedaría abierta para siempre y no se contaría nunca.
      final unMotor = Comportamiento();
      await unMotor.arrancar(api: _apiQueNoSeUsa(), instalacionId: 'i_1', config: null);
      unMotor.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      unMotor.soltar(); // y el sistema la mata acá, sin más avisos

      final otro = Comportamiento();
      await otro.arrancar(api: _apiQueNoSeUsa(), instalacionId: 'i_1', config: null);
      final eventos = await otro.cola.leer();
      final cierre =
          eventos.firstWhere((e) => e.tipo == TipoDeEvento.sesionCierra);
      expect(cierre.ms, isNotNull);
      expect(cierre.datos['cerro_la_app'], isTrue,
          reason: 'este cierre se dedujo, no se observó, y hay que poder distinguirlo');
      // Dos arranques de la aplicación, dos aperturas y UN cierre: el de la sesión que
      // murió. La de ahora sigue abierta y se cerrará cuando termine.
      expect(eventos.where((e) => e.tipo == TipoDeEvento.sesionAbre).length, 2);
      expect(eventos.where((e) => e.tipo == TipoDeEvento.sesionCierra).length, 1);
      otro.soltar();
    });

    test('llamar a arrancar dos veces no abre dos sesiones', () async {
      // Un reinicio en caliente, o una integración que llama a `init()` dos veces: serían
      // dos aperturas y un solo cierre, y la serie mostraría sesiones que nadie tuvo.
      final motor = Comportamiento();
      await motor.arrancar(api: _apiQueNoSeUsa(), instalacionId: 'i_1', config: null);
      await motor.arrancar(api: _apiQueNoSeUsa(), instalacionId: 'i_1', config: null);
      final abre = (await motor.cola.leer())
          .where((e) => e.tipo == TipoDeEvento.sesionAbre)
          .length;
      expect(abre, 1);
      motor.soltar();
    });

    test('el servidor lo puede apagar; si no dice nada, mide', () async {
      // Hoy el catálogo del back no tiene `comportamiento`, así que la configuración no
      // dice nada y el módulo corre — que es lo que hace falta para «acumular desde el día
      // uno». El día que el catálogo lo tenga y lo apague, esto se calla.
      final prendido = Comportamiento();
      await prendido.arrancar(api: _apiQueNoSeUsa(), instalacionId: 'i_1', config: null);
      expect((await prendido.estado()).activo, isTrue);
      expect((await prendido.cola.leer()), isNotEmpty);
      prendido.soltar();
    });
  });
}

/// Un cliente apuntando a un puerto donde no hay nadie.
///
/// Estas pruebas miran la COLA, no la red: nunca se llama a `transmitir()`. Se le pasa un
/// cliente igual porque `arrancar` lo exige, y lo exige porque un módulo sin a quién
/// hablarle no debería creer que está transmitiendo.
AkPushApi _apiQueNoSeUsa() =>
    AkPushApi(apiKey: 'pk_test.deprueba', baseUrl: 'http://127.0.0.1:1');
