import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:app_settings/app_settings.dart' show AppSettings, AppSettingsType;

/// Abre los ajustes de ESTA aplicación en el teléfono.
///
/// 🔴 Escrito acá y no traído de `permission_handler` a propósito. Ese paquete declara
/// `MANAGE_EXTERNAL_STORAGE` y `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` en su manifest, y el
/// fusionador de Android los inyecta en cualquier aplicación que instale este SDK, los use
/// o no — el primero además obliga a llenar un formulario especial en Google Play. Un SDK
/// que se instala en la aplicación de otro no puede cobrarle ese peaje.
Future<bool> openAppSettings() async {
  try {
    await AppSettings.openAppSettings(type: AppSettingsType.notification);
    return true;
  } catch (_) {
    return false;
  }
}

/// El permiso de notificaciones, y sobre todo **cuándo** se pide.
///
/// ## El diálogo del sistema se gasta
///
/// No es una pregunta que se pueda repetir hasta que salga bien:
///
///  - En iPhone se muestra **una sola vez en la vida de la instalación**.
///    Después de un «no», la única salida son los Ajustes del teléfono, y ahí
///    no va casi nadie.
///  - En Android 13+ alcanzan dos descartes para que el sistema deje de
///    preguntar.
///  - En Android 12 y anteriores el diálogo directamente no existe: los avisos
///    vienen habilitados de fábrica y, si la persona los apagó, sólo los
///    Ajustes los vuelven a encender.
///
/// Por eso el peor momento posible para dispararlo es el arranque en frío: la
/// persona acabó de abrir la aplicación por primera vez, todavía no sabe qué
/// hace, y lo primero que ve es una pregunta que no puede contestar bien. El
/// «no» que se lleva ahí no se recupera nunca más.
///
/// ## Por eso existe la «pregunta blanda»
///
/// La aplicación muestra **su propia pantalla** —su marca, sus palabras, en el
/// momento en que el aviso ya tiene sentido: después de la primera compra,
/// cuando queda un pago pendiente, al terminar el alta— explicando para qué
/// sirven los avisos. Y sólo si la persona dice que sí ahí se llama a [pedir],
/// que es lo que dispara el diálogo del sistema.
///
/// Eso convierte un «no» irreversible en un «ahora no» reversible: quien dice
/// que no en la pantalla de la aplicación se lo puede volver a ofrecer la
/// semana que viene, porque el diálogo del sistema sigue entero. Quien dice que
/// no en el diálogo del sistema no vuelve.
///
/// **Este paquete no dibuja esa pantalla** —es de la aplicación, y tiene que
/// serlo—, pero la hace posible. El orden es:
///
/// ```dart
/// final gestor = GestorDePermiso();
/// final estado = await gestor.estadoActual();
///
/// if (estado.permiteRecibir) return;                 // ya está, no molestar
/// if (estado.soloQuedanLosAjustes) {                 // el diálogo ya no existe
///   if (await miPantallaDeAjustes()) await gestor.abrirAjustes();
///   return;
/// }
/// if (estado.puedeVolverAPreguntarse) {
///   if (await miPantallaQueExplica()) await gestor.pedir();
/// }
/// ```
enum EstadoDelPermiso {
  /// Nadie preguntó todavía. Es el único estado en el que el diálogo del
  /// sistema está entero, y por eso el único que hay que cuidar.
  sinPreguntar,

  /// Hay permiso. Los avisos llegan y se ven.
  concedido,

  /// Dijo que no, pero el sistema todavía admite otro diálogo.
  ///
  /// En los hechos esto **sólo pasa en Android 13+**: es la única plataforma
  /// que da una segunda oportunidad. Se gasta rápido, así que se usa después de
  /// la pregunta blanda, no antes.
  denegado,

  /// Dijo que no y el diálogo del sistema ya no se va a mostrar más.
  ///
  /// Lo único que queda es [GestorDePermiso.abrirAjustes]. Mostrar acá una
  /// pantalla que promete activar los avisos con un botón es mentirle a la
  /// persona: el botón no puede hacer nada.
  denegadoParaSiempre,

  /// iOS entrega los avisos en silencio, directo al centro de notificaciones,
  /// sin interrumpir. La persona nunca vio un diálogo.
  provisional;

  /// Si tiene sentido volver a mostrar el diálogo del sistema.
  ///
  /// Es la pregunta que decide si la pantalla propia de la aplicación —la
  /// pregunta blanda— sirve para algo: si esto es `false`, esa pantalla termina
  /// en un botón que no hace nada, y eso se paga en confianza.
  ///
  /// En [provisional] es `true` porque el diálogo todavía tiene algo que
  /// ofrecer: pasar de avisos silenciosos a avisos que interrumpen.
  bool get puedeVolverAPreguntarse => switch (this) {
        EstadoDelPermiso.sinPreguntar => true,
        EstadoDelPermiso.denegado => true,
        EstadoDelPermiso.provisional => true,
        EstadoDelPermiso.concedido => false,
        EstadoDelPermiso.denegadoParaSiempre => false,
      };

  /// Si con este estado el teléfono puede recibir avisos.
  ///
  /// [provisional] cuenta: llegan, aunque en silencio. Es lo que el servicio
  /// necesita saber para no pagar envíos a un teléfono que no muestra nada.
  bool get permiteRecibir =>
      this == EstadoDelPermiso.concedido ||
      this == EstadoDelPermiso.provisional;

  /// Si el único camino que queda es mandar a la persona a los Ajustes.
  ///
  /// Separado de [puedeVolverAPreguntarse] a propósito: no son opuestos.
  /// [concedido] no admite diálogo y tampoco necesita Ajustes.
  bool get soloQuedanLosAjustes => this == EstadoDelPermiso.denegadoParaSiempre;
}

/// Lee, pide y —cuando ya no queda otra— rodea el permiso de notificaciones.
///
/// Envuelve `firebase_messaging` para el estado y `app_settings` para la
/// puerta a los Ajustes. Son dos paquetes pero **una sola autoridad**: el estado
/// lo dicta siempre Firebase, que es el mismo SDK que emite el token. Preguntar
/// el estado por dos caminos distintos es la forma de tener dos respuestas que
/// no coinciden y no saber a cuál creerle.
class GestorDePermiso {
  GestorDePermiso({
    FirebaseMessaging? mensajeria,
    Future<bool> Function()? abridorDeAjustes,
  })  : _mensajeria = mensajeria,
        _abridorDeAjustes = abridorDeAjustes ?? openAppSettings;

  final FirebaseMessaging? _mensajeria;
  final Future<bool> Function() _abridorDeAjustes;

  /// Se resuelve tarde y no en el constructor porque `FirebaseMessaging.instance`
  /// revienta si Firebase todavía no arrancó, y el gestor se construye antes de
  /// que la configuración remota haya llegado.
  FirebaseMessaging get _fcm => _mensajeria ?? FirebaseMessaging.instance;

  int? _nivelDeAndroid;
  bool _nivelYaConsultado = false;

  /// Qué contestó —o no contestó todavía— la persona.
  ///
  /// No dispara ningún diálogo: se puede llamar en cada arranque sin gastar
  /// nada. Y hay que llamarlo de nuevo cada vez que la aplicación vuelve del
  /// segundo plano, porque el permiso se cambia desde los Ajustes del teléfono
  /// y **nada le avisa a la aplicación** cuando eso pasa.
  Future<EstadoDelPermiso> estadoActual() async {
    try {
      final ajustes = await _fcm.getNotificationSettings();
      return _traducir(ajustes.authorizationStatus);
    } catch (_) {
      // No saber no es lo mismo que tener la puerta cerrada. [sinPreguntar] es
      // el único estado que no cierra ningún camino; contestar
      // [denegadoParaSiempre] mandaría a la persona a los Ajustes a arreglar un
      // problema que no es suyo.
      return EstadoDelPermiso.sinPreguntar;
    }
  }

  /// Dispara el diálogo del SISTEMA. Esto es lo que se gasta.
  ///
  /// Llamarlo con la persona todavía sin contexto —en `init()`, en el arranque
  /// en frío— es exactamente lo que este archivo existe para evitar. Se llama
  /// cuando la persona ya dijo que sí en la pantalla propia de la aplicación.
  ///
  /// Devuelve el estado que quedó, que no siempre es el que se esperaba: en
  /// Android, pedir cuando ya está [EstadoDelPermiso.denegadoParaSiempre] no
  /// muestra nada y devuelve ese mismo estado.
  Future<EstadoDelPermiso> pedir() async {
    try {
      final ajustes = await _fcm.requestPermission();
      return _traducir(ajustes.authorizationStatus);
    } catch (_) {
      // Si el canal nativo falló, el diálogo no llegó a mostrarse y por lo tanto
      // no se gastó nada: el estado real sigue siendo el que había.
      return estadoActual();
    }
  }

  /// Abre la ficha de la aplicación en los Ajustes del teléfono.
  ///
  /// Es lo único que queda cuando el estado es
  /// [EstadoDelPermiso.denegadoParaSiempre]. Abre la ficha de la aplicación y
  /// no la pantalla exacta de notificaciones porque no hay una API que lleve
  /// directo a esa pantalla en las dos plataformas; desde la ficha, los avisos
  /// están a un toque en las dos.
  ///
  /// Devuelve si se pudo abrir, **no** si la persona activó algo. Lo segundo no
  /// se puede saber desde acá: hay que volver a llamar a [estadoActual] cuando
  /// la aplicación vuelve del segundo plano.
  Future<bool> abrirAjustes() async {
    try {
      return await _abridorDeAjustes();
    } catch (_) {
      // Hay teléfonos —capas de fabricante, perfiles de trabajo— donde no se
      // puede abrir. Devolver `false` deja que la aplicación muestre las
      // instrucciones a mano en vez de quedarse esperando una pantalla que no
      // va a aparecer.
      return false;
    }
  }

  Future<EstadoDelPermiso> _traducir(AuthorizationStatus estado) async =>
      switch (estado) {
        AuthorizationStatus.authorized => EstadoDelPermiso.concedido,
        AuthorizationStatus.provisional => EstadoDelPermiso.provisional,
        AuthorizationStatus.notDetermined => EstadoDelPermiso.sinPreguntar,
        AuthorizationStatus.deniedPermanently =>
          EstadoDelPermiso.denegadoParaSiempre,
        // El «no» crudo no significa lo mismo en todos lados, y de eso depende
        // si la aplicación puede volver a ofrecer o tiene que mandar a los
        // Ajustes.
        AuthorizationStatus.denied => await _queSignificaDenegado(),
      };

  /// Un `denied` de Firebase sólo es reversible en Android 13+.
  ///
  /// En iPhone, Firebase reporta el «no» definitivo como `denied` a secas —no
  /// usa `deniedPermanently`—, así que tomarlo literal haría que la aplicación
  /// ofreciera para siempre un botón que ya no puede mostrar ningún diálogo. Y
  /// en Android 12 y anteriores no existe permiso en tiempo de ejecución: un
  /// `denied` ahí significa que la persona apagó los avisos desde los Ajustes,
  /// y sólo desde ahí se vuelven a encender.
  Future<EstadoDelPermiso> _queSignificaDenegado() async {
    if (kIsWeb || !Platform.isAndroid) {
      return EstadoDelPermiso.denegadoParaSiempre;
    }

    final nivel = await _leerNivelDeAndroid();

    // Si no se pudo leer el nivel, se supone que la segunda oportunidad existe.
    // Equivocarse para este lado cuesta una pantalla propia que no termina en
    // nada; para el otro lado cuesta tirar a la basura la última chance real de
    // recuperar a esa persona.
    if (nivel == null || nivel >= 33) return EstadoDelPermiso.denegado;

    return EstadoDelPermiso.denegadoParaSiempre;
  }

  /// La versión del sistema no cambia mientras el proceso vive, así que se
  /// consulta una sola vez: [estadoActual] se llama en cada vuelta del segundo
  /// plano y no tiene por qué pagar un salto al canal nativo cada vez.
  Future<int?> _leerNivelDeAndroid() async {
    if (_nivelYaConsultado) return _nivelDeAndroid;
    _nivelYaConsultado = true;
    try {
      _nivelDeAndroid = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    } catch (_) {
      _nivelDeAndroid = null;
    }
    return _nivelDeAndroid;
  }
}
