import 'package:hz_collection_sdk/hz_collection_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RutaDelAviso.desde', () {
    test('un aviso sin ruta no es un error, es null', () {
      const m = PushMessage(data: {'pushLogId': '6a94', 'code_event': 'NC-9'});
      expect(RutaDelAviso.desde(m), isNull);
      expect(m.tieneRuta, isFalse);
      expect(m.ruta, isNull);
    });

    test('resuelve los marcadores con los parámetros sueltos', () {
      const m = PushMessage(data: {
        'ruta': '/compras/:id',
        'ruta_id': '9912',
        'ruta_tab': 'pagos',
      });
      final r = RutaDelAviso.desde(m)!;
      expect(r.cruda, '/compras/:id');
      expect(r.destino, '/compras/9912');
      expect(r.parametros, {'id': '9912', 'tab': 'pagos'});
      expect(r.tieneRuta, isTrue);
      expect(m.tieneRuta, isTrue);
    });

    test('una ruta ya resuelta viaja igual', () {
      const m = PushMessage(data: {'ruta': '/compras/9912'});
      expect(RutaDelAviso.desde(m)!.destino, '/compras/9912');
    });

    test('la consulta de la ruta entra como parámetro y se conserva', () {
      const m = PushMessage(data: {'ruta': '/compras/9912?tab=pagos'});
      final r = RutaDelAviso.desde(m)!;
      expect(r.parametros, {'tab': 'pagos'});
      expect(r.destino, '/compras/9912?tab=pagos');
    });

    test('el parámetro explícito le gana a la consulta, también en el destino',
        () {
      // Los dos tienen que decir lo mismo. `destino` es lo que se le pasa al
      // navegador, así que una precedencia que valiera sólo para `parametros`
      // abriría la pestaña vieja mientras el objeto dice la nueva.
      const m = PushMessage(data: {
        'ruta': '/compras/:id?tab=viejo',
        'ruta_id': '9912',
        'ruta_tab': 'nuevo',
      });
      final r = RutaDelAviso.desde(m)!;
      expect(r.parametros['tab'], 'nuevo');
      expect(r.destino, '/compras/9912?tab=nuevo');
    });

    test('lo que la consulta no contradice viaja tal cual vino', () {
      // Pisar de más sería reescribir la consulta entera y cambiarle el
      // escapado a rutas que hoy funcionan.
      const m = PushMessage(data: {
        'ruta': '/buscar?q=pago%20de%20cuota&orden=fecha',
        'ruta_id': '9912',
      });
      final r = RutaDelAviso.desde(m)!;
      expect(r.destino, '/buscar?q=pago%20de%20cuota&orden=fecha');
      expect(r.parametros['q'], 'pago de cuota');
    });

    test('una consulta mal escapada no se lleva puesto el ruteo', () {
      // Llevar a la pantalla sin un parámetro es mejor que no llevar a ninguna:
      // el camino sigue siendo válido aunque la consulta no se pueda leer.
      const m = PushMessage(data: {
        'ruta': '/compras/:id?tab=%E0%A4&otro=%FF',
        'ruta_id': '9912',
      });
      final r = RutaDelAviso.desde(m)!;
      expect(r.destino, startsWith('/compras/9912?'));
      expect(r.parametros['id'], '9912');
    });

    test('un marcador sin valor se queda literal, para que el fallo se vea', () {
      const m = PushMessage(data: {'ruta': '/compras/:id'});
      expect(RutaDelAviso.desde(m)!.destino, '/compras/:id');
    });

    test('las claves del paquete no se cuelan como parámetros', () {
      const m = PushMessage(data: {
        'ruta': '/inicio',
        'pushLogId': '6a94',
        'type': 'PAGARE_PENDING',
        'channelId': 'default',
      });
      expect(RutaDelAviso.desde(m)!.parametros, isEmpty);
    });

    test('una ruta vacía o en blanco es no traer ruta', () {
      expect(RutaDelAviso.desde(const PushMessage(data: {'ruta': '   '})), isNull);
      expect(RutaDelAviso.desde(const PushMessage(data: {'ruta': ''})), isNull);
    });

    test('los parámetros son de solo lectura', () {
      const m = PushMessage(data: {'ruta': '/x', 'ruta_a': '1'});
      expect(() => RutaDelAviso.desde(m)!.parametros['b'] = '2', throwsUnsupportedError);
    });
  });

  group('IntencionPendiente', () {
    test('consumir devuelve una vez y limpia', () {
      final i = IntencionPendiente();
      expect(i.consumir(), isNull);

      i.guardar(RutaDelAviso(cruda: '/compras/9912'));
      expect(i.hayPendiente, isTrue);
      expect(i.consumir()!.destino, '/compras/9912');
      expect(i.consumir(), isNull);
      expect(i.hayPendiente, isFalse);
    });

    test('un aviso sin ruta no pisa la intención que nadie consumió', () {
      final i = IntencionPendiente();
      expect(
        i.guardarDesde(const PushMessage(data: {'ruta': '/compras/:id', 'ruta_id': '9912'})),
        isTrue,
      );
      expect(i.guardarDesde(const PushMessage(data: {'code_event': 'NC-9'})), isFalse);
      expect(i.pendiente!.destino, '/compras/9912');
    });

    test('vale la última: dos toques sin consumir dejan el segundo', () {
      final i = IntencionPendiente();
      i.guardar(RutaDelAviso(cruda: '/a'));
      i.guardar(RutaDelAviso(cruda: '/b'));
      expect(i.consumir()!.destino, '/b');
    });

    test('alLlegar cubre la llegada en frío: ya estaba guardada al suscribirse',
        () async {
      final i = IntencionPendiente();
      i.guardar(RutaDelAviso(cruda: '/compras/9912'));

      final vistas = <String>[];
      final cortar = i.alLlegar((r) => vistas.add(r.destino));
      await Future<void>.delayed(Duration.zero);

      expect(vistas, ['/compras/9912']);
      expect(i.hayPendiente, isFalse);
      cortar();
    });

    test('alLlegar cubre la caliente: llega con el consumidor ya montado',
        () async {
      final i = IntencionPendiente();
      final vistas = <String>[];
      final cortar = i.alLlegar((r) => vistas.add(r.destino));
      await Future<void>.delayed(Duration.zero);
      expect(vistas, isEmpty);

      i.guardar(RutaDelAviso(cruda: '/a'));
      await Future<void>.delayed(Duration.zero);
      i.guardar(RutaDelAviso(cruda: '/b'));
      await Future<void>.delayed(Duration.zero);

      expect(vistas, ['/a', '/b']);
      cortar();
    });

    test('cortar la suscripción deja de entregar', () async {
      final i = IntencionPendiente();
      final vistas = <String>[];
      final cortar = i.alLlegar((r) => vistas.add(r.destino));
      await Future<void>.delayed(Duration.zero);
      cortar();

      i.guardar(RutaDelAviso(cruda: '/a'));
      await Future<void>.delayed(Duration.zero);

      expect(vistas, isEmpty);
      expect(i.hayPendiente, isTrue);
    });

    test('limpiar tira la intención sin entregarla', () async {
      final i = IntencionPendiente();
      final vistas = <String>[];
      final cortar = i.alLlegar((r) => vistas.add(r.destino));
      i.guardar(RutaDelAviso(cruda: '/a'));
      i.limpiar();
      await Future<void>.delayed(Duration.zero);

      expect(vistas, isEmpty);
      expect(i.hayPendiente, isFalse);
      cortar();
    });

    test('cortar alcanza también al toque que ya venía en camino', () async {
      // El caso real: el aviso se toca justo mientras la pantalla se está
      // desmontando. El aviso ya disparó la entrega y `dispose` corre en el
      // mismo cuadro, antes de que la microtarea llegue a consumir.
      //
      // Si darse de baja no alcanzara a esa entrega, la ruta se la lleva un
      // consumidor muerto —navega sobre un `State` desmontado— y además queda
      // consumida, así que la pantalla que se monta después no encuentra nada.
      // El toque no va a ningún lado y no deja rastro de por qué.
      final i = IntencionPendiente();
      final vistas = <String>[];
      final cortar = i.alLlegar((r) => vistas.add(r.destino));
      await Future<void>.delayed(Duration.zero);

      i.guardar(RutaDelAviso(cruda: '/compras/9912'));
      cortar();
      await Future<void>.delayed(Duration.zero);

      expect(vistas, isEmpty, reason: 'ese consumidor ya estaba muerto');
      expect(i.hayPendiente, isTrue, reason: 'la intención le toca al próximo');

      // Y el que se monta después sí la recibe: es lo que hace que el toque
      // sobreviva al cambio de pantalla en vez de perderse.
      final vistasDelNuevo = <String>[];
      final cortarNuevo = i.alLlegar((r) => vistasDelNuevo.add(r.destino));
      await Future<void>.delayed(Duration.zero);

      expect(vistasDelNuevo, ['/compras/9912']);
      cortarNuevo();
    });

    test('con dos consumidores vivos, la ruta se navega una sola vez',
        () async {
      // Dos pantallas suscritas a la vez pasa en cualquier app con pestañas.
      // Entregarles a las dos abriría el destino dos veces, que es el error que
      // la persona ve como «se me abrió solo dos veces».
      final i = IntencionPendiente();
      final primera = <String>[];
      final segunda = <String>[];
      final cortarPrimera = i.alLlegar((r) => primera.add(r.destino));
      final cortarSegunda = i.alLlegar((r) => segunda.add(r.destino));

      i.guardar(RutaDelAviso(cruda: '/compras/9912'));
      await Future<void>.delayed(Duration.zero);

      expect(primera.length + segunda.length, 1);
      cortarPrimera();
      cortarSegunda();
    });

    test('es observable: avisa al guardar y al consumir', () {
      final i = IntencionPendiente();
      var avisos = 0;
      i.addListener(() => avisos++);

      i.guardar(RutaDelAviso(cruda: '/a'));
      expect(avisos, 1);
      i.consumir();
      expect(avisos, 2);
      i.consumir();
      expect(avisos, 2);
    });

    test('la intención sobrevive a que nadie esté escuchando', () async {
      // El toque en frío: llega con la aplicación muerta y se guarda mucho
      // antes de que exista el navegador. Si esto no se conservara, el 100% de
      // los toques con la app cerrada no llevarían a ninguna parte.
      final i = IntencionPendiente();
      i.guardarDesde(const PushMessage(data: {'ruta': '/compras/9912'}));

      await Future<void>.delayed(Duration.zero);
      expect(i.hayPendiente, isTrue);

      final vistas = <String>[];
      final cortar = i.alLlegar((r) => vistas.add(r.destino));
      await Future<void>.delayed(Duration.zero);

      expect(vistas, ['/compras/9912']);
      cortar();
    });
  });
}
