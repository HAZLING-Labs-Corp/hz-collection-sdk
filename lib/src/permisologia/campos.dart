/// LAS FICHAS DE CADA CAMPO — qué se manda y cómo, en un archivo sin Flutter adentro.
///
/// 🔴 ESTÁN ACÁ Y NO EN SU MÓDULO, y el motivo es concreto: `bin/catalogo.dart` las emite
/// como JSON para que la consola pueda mostrarle a una persona QUÉ SE SABE DE ELLA, con la
/// frase que escribió quien declaró el campo. Ese generador es Dart puro y corre sin
/// dispositivo; los módulos importan `package:flutter/services.dart` y `device_info_plus`,
/// que arrastran `dart:ui` y no compilan fuera de una aplicación.
///
/// Mientras las fichas vivían dentro de los módulos, generar el catálogo era imposible — y
/// la alternativa habría sido copiar noventa y cinco rótulos al front, que es exactamente la
/// segunda lista que todo este diseño evita.
library;

import 'transformar.dart';

/// Los campos que este módulo manda, y qué manda cada uno.
///
/// 🔴 Todos son `taICual` y eso está bien: ninguno viene de algo que haya escrito una
/// persona. Son propiedades del aparato y booleanos calculados. Ver `transformar.dart` — la
/// regla es que un campo que PUEDA llevar texto de alguien no use `taICual`, y acá ninguno
/// puede.
const List<CampoRecolectado> camposDeAutenticidad = [
  CampoRecolectado('esFisico', Transformacion.taICual,
      queManda: 'si el sistema dice que es un teléfono de verdad y no un emulador',
      paraQue: 'Autenticidad, la base de todo: si el sistema mismo declara que es un teléfono real y no un emulador.'),
  CampoRecolectado('pareceEmulador', Transformacion.taICual,
      queManda: 'si las propiedades del aparato coinciden con las de un emulador conocido',
      paraQue: 'Antifraude: si las propiedades del aparato coinciden con las de un emulador conocido.',
      computada: true),
  CampoRecolectado('senalesDeEmulador', Transformacion.taICual,
      queManda: 'cuántas señales de emulador se encontraron, de las que se miran',
      paraQue: 'Antifraude: cuántas señales de emulador se encontraron. El que arma el puntaje decide el corte.',
      computada: true),
  CampoRecolectado('senalesDeRoot', Transformacion.taICual,
      queManda: 'cuántas señales de root se encontraron. Cero no quiere decir limpio',
      paraQue: 'Antifraude: cuántas señales de root. Cero no quiere decir limpio, pero muchas sí encienden la alarma.',
      computada: true),
  CampoRecolectado('compilacionDePrueba', Transformacion.taICual,
      queManda: 'si el sistema operativo está firmado con llaves de prueba y no de fábrica',
      paraQue: 'Antifraude: un sistema firmado con llaves de prueba no es de fábrica; es una señal de root barata.',
      computada: true),
];

/// LOS SIETE GRUPOS, con el título que se muestra y qué revela cada uno.
///
/// 🔴 Vive acá y no en la consola. El nombre de un grupo y la frase que explica qué revela
/// son lo que ve una persona que pregunta qué se sabe de ella; escribirlos en el front habría
/// dejado dos listas que empiezan iguales y se separan en el primer campo que se agregue de
/// un solo lado. `bin/catalogo.dart` las emite y el servicio las sirve.
class GrupoDeSenales {
  final String prefijo;
  final String titulo;
  final String queRevela;

  /// En qué plataformas EXISTE este grupo.
  ///
  /// 🔴 AGREGADO EL 2026-09-11, Y NO ES UN DATO DE ADORNO: sin él, la consola de un comercio
  /// ofrece configurar en iOS grupos que iOS no da, y el comercio los prende creyendo que va a
  /// medir algo. No falla — simplemente no llega nada, que es la peor forma de fallar.
  ///
  /// Medido contando las claves que reporta cada plugin nativo, no declarado a ojo:
  ///
  /// | grupo    | Android | iOS |
  /// |----------|---------|-----|
  /// | `hd_`    | 35      | 20  |
  /// | `cfg_`   | 1       | 0   |
  /// | `acc_`   | 7       | 0   |
  /// | `bat_`   | 7       | 3   |
  /// | `sen_`   | 9       | 7   |
  /// | `red_`   | 7       | 4   |
  /// | `ent_`   | 8       | 0   |
  /// | `canal_` | 9       | 0   |
  /// | `app_`   | 8       | 0   |
  /// | `usr_`   | 3       | 0   |
  ///
  /// **Cinco de los diez no existen en iOS**, y entre ellos está `acc_` —accesibilidad—, que es
  /// la que detecta el control remoto y la que más pesa en el portón de fraude.
  ///
  /// ⚠️ Se declara acá y se comprueba con `bin/verificar-plataformas.dart`: una marca a mano se
  /// desincroniza el día que alguien agregue una señal al plugin de iOS y se olvide de esto.
  final List<String> plataformas;

  const GrupoDeSenales(this.prefijo, this.titulo, this.queRevela,
      {this.plataformas = const ['ANDROID', 'IOS']});
}

const List<GrupoDeSenales> gruposDeSenales = [
  GrupoDeSenales('hd_', 'Huella digital',
      'Qué aparato es, qué idioma y qué zona horaria declara, de qué país es la SIM y a qué '
      'hora se midió. Es el grupo con más respaldo: un estudio de NBER sobre 270.000 compras '
      'midió que estos datos solos predicen tan bien como un buró de crédito.'),
  GrupoDeSenales('cfg_', 'Configuración del sistema',
      'Cómo está configurado el teléfono: si tiene la depuración por USB activa, si permite '
      'instalar aplicaciones de fuera de la tienda, si las animaciones están apagadas. Nada '
      'de esto dice quién es la persona; dice cómo está armado el aparato.',
      plataformas: ['ANDROID']),
  GrupoDeSenales('acc_', 'Accesibilidad',
      'Si hay servicios de accesibilidad activos y qué pueden hacer: leer la pantalla, tocar '
      'por la persona. Es lo que detecta una herramienta de control remoto. No se manda cuáles '
      'son, sólo cuántos y qué pueden.',
      plataformas: ['ANDROID']),
  GrupoDeSenales('bat_', 'Batería a fondo',
      'Voltaje, temperatura, salud y tecnología de la batería. Un emulador devuelve valores '
      'redondos que un teléfono de verdad nunca da.'),
  GrupoDeSenales('sen_', 'Sensores',
      'Cuántos sensores tiene y cuáles de los básicos existen. Un teléfono real tiene entre '
      'quince y treinta; un emulador, tres o cuatro. No se manda el fabricante de cada uno.'),
  GrupoDeSenales('red_', 'Red',
      'Por dónde está conectado y a qué velocidad, y si hay una VPN activa. No se manda el '
      'nombre de la red WiFi: el nombre de una red doméstica identifica un hogar.'),
  GrupoDeSenales('ent_', 'Entregabilidad',
      'Si el push va a llegar de verdad y lo va a ver: avisos permitidos, canal silenciado, '
      'ahorro de batería, Doze, restricción en segundo plano, No molestar, pantalla encendida '
      'y nivel de señal. Todo sin pedir un permiso. El proveedor arma con esto su índice.',
      plataformas: ['ANDROID']),
  GrupoDeSenales('canal_', 'Canales alcanzables',
      'Qué apps de contacto tiene instaladas —WhatsApp, Telegram, redes—, para elegir por dónde '
      'mandarle. Sólo dice si están instaladas, NO si están activas ni qué hace en ellas. Es la '
      'lista puntual que Google Play permite, sin ver todas las apps del teléfono.',
      plataformas: ['ANDROID']),
  GrupoDeSenales('app_', 'Vida económica',
      'Qué apps de dinero, compras, mapas y suscripciones tiene instaladas. Igual que los '
      'canales, es la lista PUNTUAL que Google Play permite y sólo dice si están instaladas: '
      'nunca qué hace en ellas ni cuánto las abre, que exigiría un permiso vetado. '
      '🔴 Y la trampa: tener pocas apps no es riesgo de crédito, es pobreza. Sirven si '
      'conservan poder predictivo controlando por nivel de ingreso; si no, se sacan.',
      plataformas: ['ANDROID']),
  GrupoDeSenales('usr_', 'Perfil de usuario',
      'Si la aplicación corre en el usuario principal del teléfono o en un perfil secundario, '
      'y si el aparato está en modo demostración.',
      plataformas: ['ANDROID']),
];

/// A qué grupo pertenece un campo. `null` si nadie lo declaró.
GrupoDeSenales? grupoDe(String campo) {
  for (final g in gruposDeSenales) {
    if (campo.startsWith(g.prefijo)) return g;
  }
  return null;
}

/// Las fichas. Cada una dice QUÉ MANDA, en castellano: es el texto que se le puede mostrar a
/// una persona que pregunte qué se sabe de ella, y a un comercio que quiera saber qué está
/// recolectando. Un campo cuyo «qué manda» no se puede escribir en una frase es un campo que
/// nadie entiende, incluidos nosotros.
const List<CampoRecolectado> camposDeSenales = [
  // ── Configuración del sistema ─────────────────────────────────────────────────────────
  CampoRecolectado('cfg_adb_enabled', Transformacion.taICual,
      queManda: 'si la depuración por USB está activa. No es normal en un teléfono de uso diario',
      paraQue: 'Antifraude: la depuración por USB abierta es de un teléfono manipulado o de una granja, no de un usuario común.'),
  CampoRecolectado('cfg_development_settings_enabled', Transformacion.taICual,
      queManda: 'si las opciones de desarrollador están activas',
      paraQue: 'Antifraude: casi nadie prende las opciones de desarrollador para pagar cuotas; su presencia sube el riesgo.'),
  CampoRecolectado('cfg_debug_app_es_la_nuestra', Transformacion.taICual,
      queManda: 'si la aplicación marcada como depurable es la nuestra. El nombre de otra no se manda',
      paraQue: 'Antifraude: si NUESTRA app está en modo depuración, alguien la está inspeccionando.',
      computada: true),
  CampoRecolectado('cfg_install_non_market_apps', Transformacion.taICual,
      queManda: 'si permite instalar aplicaciones de fuera de la tienda',
      paraQue: 'Riesgo: permitir apps de fuera de la tienda se asocia a teléfonos con software modificado.'),
  CampoRecolectado('cfg_device_provisioned', Transformacion.taICual,
      queManda: 'si el teléfono terminó su configuración inicial',
      paraQue: 'Antifraude: un teléfono sin terminar su configuración inicial suele ser recién creado en serie.'),
  CampoRecolectado('cfg_airplane_mode_on', Transformacion.taICual,
      queManda: 'si el modo avión está prendido en este momento',
      paraQue: 'Contexto: el modo avión al medir explica por qué pueden faltar datos de red.'),
  CampoRecolectado('cfg_boot_count', Transformacion.tramo, tramoDe: 50,
      queManda: 'cuántas veces se encendió el teléfono, por tramos de cincuenta',
      paraQue: 'Antigüedad: cuántas veces se encendió aproxima cuán viejo y usado es el teléfono.'),
  CampoRecolectado('cfg_usb_mass_storage_enabled', Transformacion.taICual,
      queManda: 'si el almacenamiento por USB está habilitado',
      paraQue: 'Antifraude: el almacenamiento por USB habilitado es más común en aparatos de banco de pruebas.'),
  CampoRecolectado('cfg_window_animation_scale', Transformacion.taICual,
      queManda: 'la velocidad de las animaciones de ventana. En cero suele ser un emulador',
      paraQue: 'Antifraude clásico: la animación en cero es la firma de un emulador acelerado.'),
  CampoRecolectado('cfg_transition_animation_scale', Transformacion.taICual,
      queManda: 'la velocidad de las transiciones. En cero suele ser un emulador',
      paraQue: 'Antifraude clásico: la transición en cero delata un emulador acelerado.'),
  CampoRecolectado('cfg_animator_duration_scale', Transformacion.taICual,
      queManda: 'la duración de las animaciones. En cero suele ser un emulador',
      paraQue: 'Antifraude clásico: la animación en cero delata un emulador acelerado.'),
  CampoRecolectado('cfg_stay_on_while_plugged_in', Transformacion.taICual,
      queManda: 'si la pantalla queda encendida al enchufarlo. Típico de un aparato de granja',
      paraQue: 'Antifraude: la pantalla siempre encendida al enchufar es típico de una granja de dispositivos.'),
  CampoRecolectado('cfg_screen_off_timeout', Transformacion.taICual,
      queManda: 'a los cuántos milisegundos se apaga la pantalla sola',
      paraQue: 'Comportamiento: cómo tiene el ahorro de pantalla; un valor extremo llama la atención.'),
  CampoRecolectado('cfg_screen_brightness_mode', Transformacion.taICual,
      queManda: 'si el brillo es automático o manual',
      paraQue: 'Comportamiento: brillo automático o manual, una preferencia de un usuario real.'),
  CampoRecolectado('cfg_font_scale', Transformacion.taICual,
      queManda: 'el tamaño de letra elegido en el sistema',
      paraQue: 'Perfil: un tamaño de letra muy grande sugiere una persona mayor o con baja visión.'),
  CampoRecolectado('cfg_sound_effects_enabled', Transformacion.taICual,
      queManda: 'si los sonidos del sistema están activos',
      paraQue: 'Comportamiento: una preferencia menor que, sumada a otras, arma el perfil de un teléfono en uso.'),
  CampoRecolectado('cfg_time_12_24', Transformacion.taICual,
      queManda: 'si usa reloj de 12 o de 24 horas',
      paraQue: 'Segmentación: reloj de 12 o 24 horas es una preferencia regional y personal.'),
  CampoRecolectado('cfg_accelerometer_rotation', Transformacion.taICual,
      queManda: 'si la pantalla rota sola con el acelerómetro',
      paraQue: 'Comportamiento: si deja rotar la pantalla, una preferencia de uso cotidiano.'),
  CampoRecolectado('cfg_haptic_feedback_enabled', Transformacion.taICual,
      queManda: 'si la vibración al tocar está activa',
      paraQue: 'Comportamiento: la vibración al tocar, otra pista de un teléfono realmente usado.'),
  CampoRecolectado('cfg_default_input_method', Transformacion.presencia,
      queManda: 'si tiene teclado configurado. No se manda cuál: sería un dato de terceros',
      paraQue: 'Autenticidad leve: tener teclado configurado indica un teléfono en uso. No se lee cuál.'),
  CampoRecolectado('cfg_wifi_watchdog_on', Transformacion.taICual,
      queManda: 'un ajuste de red que en los emuladores suele estar en su valor de fábrica',
      paraQue: 'Antifraude: en su valor de fábrica es típico de un emulador que nadie usó.'),
  CampoRecolectado('cfg_wifi_num_open_networks_kept', Transformacion.taICual,
      queManda: 'cuántas redes abiertas recuerda el sistema',
      paraQue: 'Antifraude: cuántas redes recuerda; en cero cerrado sugiere un aparato sin historia.'),
  CampoRecolectado('cfg_wifi_max_dhcp_retry_count', Transformacion.taICual,
      queManda: 'cuántos reintentos de red permite el sistema',
      paraQue: 'Antifraude: un valor de fábrica en este ajuste de red apunta a un emulador.'),
  CampoRecolectado('cfg_end_button_behavior', Transformacion.taICual,
      queManda: 'qué hace el botón de colgar',
      paraQue: 'Comportamiento: una preferencia de telefonía de un teléfono realmente configurado.'),
  CampoRecolectado('cfg_dtmf_tone', Transformacion.taICual,
      queManda: 'si suenan los tonos al marcar',
      paraQue: 'Comportamiento: si suenan los tonos al marcar, otra preferencia de uso real.'),
  CampoRecolectado('cfg_accessibility_enabled', Transformacion.taICual,
      queManda: 'si la accesibilidad del sistema está activa',
      paraQue: 'Contexto: si hay accesibilidad activa a nivel sistema (se detalla en el grupo Accesibilidad).'),
  CampoRecolectado('cfg_contact_metadata_sync_enabled', Transformacion.taICual,
      queManda: 'si sincroniza datos de contactos. NO se leen los contactos',
      paraQue: 'Comportamiento: si sincroniza datos de contactos. NO se leen los contactos.'),

  // ── Accesibilidad ─────────────────────────────────────────────────────────────────────
  CampoRecolectado('acc_prendida', Transformacion.taICual,
      queManda: 'si hay accesibilidad activa en el teléfono',
      paraQue: 'Antifraude: hay accesibilidad activa. Se mira con lupa porque es la vía de las estafas por control remoto.'),
  CampoRecolectado('acc_exploracion_tactil', Transformacion.taICual,
      queManda: 'si la exploración táctil está activa',
      paraQue: 'Contexto: la exploración táctil suele indicar una persona con baja visión, no fraude.'),
  CampoRecolectado('acc_activos', Transformacion.taICual,
      queManda: 'cuántos servicios de accesibilidad están activos ahora',
      paraQue: 'Antifraude: cuántos servicios de accesibilidad corren ahora; muchos o desconocidos suben el riesgo.',
      computada: true),
  CampoRecolectado('acc_instalados', Transformacion.taICual,
      queManda: 'cuántos hay instalados. No se manda cuáles',
      paraQue: 'Antifraude: cuántos hay instalados aunque no estén activos.',
      computada: true),
  CampoRecolectado('acc_puede_leer_la_pantalla', Transformacion.taICual,
      queManda: 'si algún servicio activo puede leer lo que hay en pantalla',
      paraQue: 'Antifraude alto: un servicio que lee la pantalla puede capturar lo que la persona ve, típico del fraude remoto.',
      computada: true),
  CampoRecolectado('acc_puede_tocar_por_vos', Transformacion.taICual,
      queManda: 'si algún servicio activo puede tocar la pantalla por la persona',
      paraQue: 'Antifraude alto: un servicio que toca por la persona puede operar la app sin ella — la señal más fuerte de estafa remota.',
      computada: true),
  CampoRecolectado('acc_activos_sin_declararse_herramienta', Transformacion.taICual,
      queManda: 'cuántos usan la accesibilidad sin declararse herramienta de accesibilidad',
      paraQue: 'Antifraude: servicios que usan la accesibilidad sin declararse herramienta — el patrón de una app maliciosa disfrazada.',
      computada: true),

  // ── Batería ───────────────────────────────────────────────────────────────────────────
  CampoRecolectado('bat_voltaje_mv', Transformacion.tramo, tramoDe: 100,
      queManda: 'el voltaje de la batería, por tramos. Los emuladores dan valores redondos',
      paraQue: 'Antifraude: los emuladores devuelven voltajes redondos que una batería real nunca da.'),
  CampoRecolectado('bat_temperatura_decimas_c', Transformacion.tramo, tramoDe: 50,
      queManda: 'la temperatura de la batería, por tramos',
      paraQue: 'Antifraude: una temperatura fija o imposible delata un emulador.'),
  CampoRecolectado('bat_tecnologia', Transformacion.taICual,
      queManda: 'de qué tipo es la batería, por ejemplo Li-ion',
      paraQue: 'Autenticidad: el tipo de batería que reporta un teléfono real.'),
  CampoRecolectado('bat_salud', Transformacion.taICual,
      queManda: 'el estado de salud que reporta la batería',
      paraQue: 'Antigüedad: la salud de la batería aproxima cuán desgastado está el teléfono.'),
  CampoRecolectado('bat_enchufado_a', Transformacion.taICual,
      queManda: 'a qué está enchufado: cargador, USB o inalámbrico',
      paraQue: 'Antifraude: siempre enchufado es típico de una granja de dispositivos.'),
  CampoRecolectado('bat_escala', Transformacion.taICual,
      queManda: 'la escala con la que el sistema informa la carga',
      paraQue: 'Autenticidad: la escala con la que informa la carga; un valor atípico sugiere emulador.'),
  CampoRecolectado('bat_presente', Transformacion.taICual,
      queManda: 'si el sistema dice que hay una batería puesta',
      paraQue: 'Antifraude: un emulador de escritorio suele reportar que no hay batería puesta.'),

  // ── Sensores ──────────────────────────────────────────────────────────────────────────
  CampoRecolectado('sen_cantidad', Transformacion.taICual,
      queManda: 'cuántos sensores tiene. Un teléfono real tiene entre quince y treinta',
      paraQue: 'Antifraude: un teléfono real tiene entre quince y treinta sensores; un emulador, tres o cuatro.',
      computada: true),
  CampoRecolectado('sen_hay_acelerometro', Transformacion.taICual, queManda: 'si tiene acelerómetro',
      paraQue: 'Autenticidad: casi todo teléfono real tiene acelerómetro; su ausencia apunta a un emulador.',
      computada: true),
  CampoRecolectado('sen_hay_giroscopio', Transformacion.taICual, queManda: 'si tiene giroscopio',
      paraQue: 'Autenticidad: la falta de giroscopio, sumada a otras, apunta a un emulador.',
      computada: true),
  CampoRecolectado('sen_hay_magnetometro', Transformacion.taICual, queManda: 'si tiene brújula',
      paraQue: 'Autenticidad: la brújula existe en teléfonos reales; su ausencia es sospechosa.',
      computada: true),
  CampoRecolectado('sen_hay_proximidad', Transformacion.taICual, queManda: 'si tiene sensor de proximidad',
      paraQue: 'Autenticidad: el sensor de proximidad casi siempre está en un teléfono real.',
      computada: true),
  CampoRecolectado('sen_hay_luz', Transformacion.taICual, queManda: 'si tiene sensor de luz',
      paraQue: 'Autenticidad: el sensor de luz es parte del equipamiento de un teléfono real.',
      computada: true),
  CampoRecolectado('sen_hay_barometro', Transformacion.taICual, queManda: 'si tiene barómetro',
      paraQue: 'Perfil: el barómetro aparece más en gama alta; ayuda a ubicar la gama.',
      computada: true),
  CampoRecolectado('sen_hay_paso', Transformacion.taICual, queManda: 'si tiene contador de pasos',
      paraQue: 'Perfil: el contador de pasos es común en teléfonos reales en uso.',
      computada: true),
  CampoRecolectado('sen_genericos', Transformacion.taICual,
      queManda: 'cuántos sensores dicen ser del fabricante genérico. En un emulador, todos',
      paraQue: 'Antifraude: sensores del fabricante genérico en bloque son la firma de un emulador.',
      computada: true),

  // ── Perfil de usuario ─────────────────────────────────────────────────────────────────
  CampoRecolectado('usr_es_el_principal', Transformacion.taICual,
      queManda: 'si la aplicación corre en el usuario principal del teléfono',
      paraQue: 'Antifraude: correr en un perfil secundario o clonado sube el riesgo.'),
  CampoRecolectado('usr_es_demo', Transformacion.taICual,
      queManda: 'si el teléfono está en modo demostración, como los de vidriera',
      paraQue: 'Antifraude: el modo demostración es el de un teléfono de vidriera, no de un cliente.'),
  CampoRecolectado('usr_en_primer_plano', Transformacion.taICual,
      queManda: 'si el usuario del sistema está en primer plano',
      paraQue: 'Contexto: si el usuario del sistema está en primer plano al medir.'),

  // ── Red ───────────────────────────────────────────────────────────────────────────────
  CampoRecolectado('red_es_wifi', Transformacion.taICual, queManda: 'si está conectado por WiFi',
      paraQue: 'Contexto: por dónde está conectado; ayuda a explicar la calidad de la señal y el comportamiento.'),
  CampoRecolectado('red_es_celular', Transformacion.taICual, queManda: 'si está conectado por datos',
      paraQue: 'Contexto: conexión por datos móviles, una pista del uso fuera de casa.'),
  CampoRecolectado('red_hay_vpn', Transformacion.taICual,
      queManda: 'si hay una VPN activa. No dice cuál ni a dónde',
      paraQue: 'Antifraude: una VPN activa puede ocultar el país real; sube el riesgo si no coincide con lo declarado.'),
  CampoRecolectado('red_sin_limite_de_datos', Transformacion.taICual,
      queManda: 'si la conexión no tiene límite de datos',
      paraQue: 'Contexto: si la conexión no tiene límite de datos, una pista del tipo de plan.'),
  CampoRecolectado('red_sin_roaming', Transformacion.taICual, queManda: 'si NO está en roaming',
      paraQue: 'Contexto: el roaming sugiere que la persona está fuera de su país.'),
  CampoRecolectado('red_bajada_kbps', Transformacion.tramo, tramoDe: 1000,
      queManda: 'la velocidad de bajada estimada, por tramos',
      paraQue: 'Contexto: la velocidad de bajada aproxima la calidad de la conexión de la persona.'),
  CampoRecolectado('red_subida_kbps', Transformacion.tramo, tramoDe: 1000,
      queManda: 'la velocidad de subida estimada, por tramos',
      paraQue: 'Contexto: la velocidad de subida, misma pista de calidad de conexión.'),

  // ── La huella digital ─────────────────────────────────────────────────────────────────
  // El grupo de NBER, el único con respaldo auditado por terceros. No lo tiene ningún
  // colector del mercado: es la única parte del plan donde vamos adelante y no atrás.
  CampoRecolectado('hd_hora_local', Transformacion.taICual,
      queManda: 'a qué hora del día se midió. Es el campo más citado del estudio de NBER',
      paraQue: 'Puntaje (NBER): la hora del alta predice riesgo; las altas de madrugada en serie son señal de granja.'),
  CampoRecolectado('hd_dia_de_semana', Transformacion.taICual,
      queManda: 'qué día de la semana se midió',
      paraQue: 'Puntaje: el día del alta, otra señal de comportamiento del estudio de NBER.'),
  CampoRecolectado('hd_zona_horaria', Transformacion.taICual,
      queManda: 'qué zona horaria tiene puesta el teléfono. No dice dónde está: dice qué declara',
      paraQue: 'Coherencia: la zona horaria declarada, para cruzar contra el país de la SIM y del sistema.'),
  CampoRecolectado('hd_minutos_de_desfase_utc', Transformacion.taICual,
      queManda: 'cuántos minutos de diferencia con la hora universal',
      paraQue: 'Coherencia: el desfase horario, la misma comprobación de consistencia en número.',
      computada: true),
  CampoRecolectado('hd_hora_automatica', Transformacion.taICual,
      queManda: 'si la hora la pone la red o la puso alguien a mano',
      paraQue: 'Antifraude: la hora puesta a mano es lo primero que toca quien burla una comprobación de fecha.'),
  CampoRecolectado('hd_zona_automatica', Transformacion.taICual,
      queManda: 'si la zona horaria la pone la red o la puso alguien a mano',
      paraQue: 'Antifraude: una zona horaria manual, igual que la hora, es sospechosa.'),
  CampoRecolectado('hd_idioma', Transformacion.taICual,
      queManda: 'en qué idioma está el teléfono',
      paraQue: 'Coherencia y segmentación: el idioma del teléfono, para cruzar con el país y para segmentar.'),
  CampoRecolectado('hd_pais_del_sistema', Transformacion.taICual,
      queManda: 'qué país declara la configuración del teléfono',
      paraQue: 'Coherencia: el país que declara el teléfono, una de las tres fuentes que se cruzan.'),
  CampoRecolectado('hd_idiomas_configurados', Transformacion.taICual,
      queManda: 'cuántos idiomas tiene configurados',
      paraQue: 'Segmentación: cuántos idiomas maneja la persona.'),
  CampoRecolectado('hd_pais_de_la_sim', Transformacion.taICual,
      queManda: 'de qué país es la SIM. NO se lee el número de teléfono ni el IMEI',
      paraQue: 'Coherencia: el país de la SIM, la fuente más difícil de falsear. NO se lee el número.'),
  CampoRecolectado('hd_pais_de_la_red', Transformacion.taICual,
      queManda: 'de qué país es la red a la que está conectado',
      paraQue: 'Coherencia: el país de la red a la que está conectado, tercera fuente que se cruza.'),
  CampoRecolectado('hd_operadora', Transformacion.taICual,
      queManda: 'el nombre de la operadora de telefonía',
      paraQue: 'Segmentación: la operadora, un dato de perfil y de mercado.'),
  CampoRecolectado('hd_estado_de_la_sim', Transformacion.taICual,
      queManda: 'si hay SIM y en qué estado está',
      paraQue: 'Contexto: si hay SIM y en qué estado; sin SIM sube el riesgo.'),
  CampoRecolectado('hd_pais_coherente', Transformacion.taICual,
      queManda: 'si el país de la configuración y el de la SIM coinciden',
      paraQue: 'Antifraude clave: si el país del sistema y el de la SIM coinciden — la incoherencia es la señal de fraude más barata que existe.',
      computada: true),
  CampoRecolectado('hd_sim_y_red_coinciden', Transformacion.taICual,
      queManda: 'si el país de la SIM y el de la red coinciden. Distinto es no probar nada solo',
      paraQue: 'Antifraude: si el país de la SIM y el de la red coinciden.',
      computada: true),
  CampoRecolectado('hd_marca', Transformacion.taICual, queManda: 'la marca del teléfono',
      paraQue: 'Puntaje (NBER): la marca del teléfono predice riesgo por sí sola casi tan bien como un buró de crédito.'),
  CampoRecolectado('hd_modelo', Transformacion.taICual, queManda: 'el modelo del teléfono',
      paraQue: 'Puntaje (NBER): el modelo afina la predicción — gama alta y gama baja se comportan distinto.'),
  CampoRecolectado('hd_version_del_sistema', Transformacion.taICual,
      queManda: 'qué versión de Android tiene',
      paraQue: 'Puntaje y antigüedad: una versión vieja de Android sugiere un teléfono viejo o abandonado.'),
  CampoRecolectado('hd_api', Transformacion.taICual,
      queManda: 'el número interno de esa versión de Android',
      paraQue: 'Igual que la versión, en número, para comparar con precisión.'),
  CampoRecolectado('hd_arquitectura', Transformacion.taICual,
      queManda: 'qué tipo de procesador tiene',
      paraQue: 'Autenticidad: el tipo de procesador; ciertos valores delatan un emulador de escritorio.'),
  CampoRecolectado('hd_nucleos', Transformacion.taICual,
      queManda: 'cuántos núcleos tiene el procesador',
      paraQue: 'Perfil: la potencia del procesador, otra pista de gama.'),
  CampoRecolectado('hd_meses_sin_parche', Transformacion.taICual,
      queManda: 'hace cuántos meses que el fabricante no le manda una actualización de seguridad',
      paraQue: 'Puntaje: un aparato que el fabricante dejó de actualizar es de gama baja o viejo, y eso se correlaciona con el riesgo.',
      computada: true),
  CampoRecolectado('hd_ram_total_mb', Transformacion.tramo, tramoDe: 512,
      queManda: 'cuánta memoria tiene, por tramos',
      paraQue: 'Perfil: la memoria total es una de las mejores pistas de gama y de capacidad de pago.'),
  CampoRecolectado('hd_ram_libre_mb', Transformacion.tramo, tramoDe: 256,
      queManda: 'cuánta memoria tenía libre al medir, por tramos',
      paraQue: 'Contexto: la memoria libre al medir.'),
  CampoRecolectado('hd_ram_en_las_ultimas', Transformacion.taICual,
      queManda: 'si el sistema estaba quedándose sin memoria al medir',
      paraQue: 'Contexto: si estaba quedándose sin memoria — un teléfono saturado.'),
  CampoRecolectado('hd_ram_poca', Transformacion.taICual,
      queManda: 'si el fabricante lo declara aparato de poca memoria',
      paraQue: 'Perfil: si el fabricante lo declara de poca memoria, es gama de entrada.'),
  CampoRecolectado('hd_densidad_dpi', Transformacion.taICual,
      queManda: 'la densidad de la pantalla',
      paraQue: 'Perfil: la densidad de pantalla, otra pista de gama.'),
  CampoRecolectado('hd_pulgadas_x10', Transformacion.tramo, tramoDe: 5,
      queManda: 'el tamaño de la pantalla en décimas de pulgada, por tramos. La resolución exacta no se manda',
      paraQue: 'Autenticidad y perfil: el tamaño físico separa un teléfono de una tableta y de un emulador de escritorio.'),
  CampoRecolectado('hd_dias_desde_la_instalacion', Transformacion.tramo, tramoDe: 7,
      queManda: 'hace cuántos días se instaló nuestra aplicación, por semanas',
      paraQue: 'Comportamiento: hace cuánto instaló la app; recién instalada sube el riesgo.'),
  CampoRecolectado('hd_dias_desde_la_actualizacion', Transformacion.tramo, tramoDe: 7,
      queManda: 'hace cuántos días se actualizó nuestra aplicación, por semanas',
      paraQue: 'Comportamiento: hace cuánto la actualizó.'),
  CampoRecolectado('hd_reinstalada', Transformacion.taICual,
      queManda: 'si nuestra aplicación se actualizó alguna vez desde que se instaló',
      paraQue: 'Comportamiento: si alguna vez la actualizó, señal de un usuario que la mantiene.',
      computada: true),
  CampoRecolectado('hd_vino_de_la_tienda', Transformacion.taICual,
      queManda: 'si nuestra aplicación se instaló desde Google Play',
      paraQue: 'Antifraude: si la app se instaló desde Google Play; lo contrario sube el riesgo.',
      computada: true),
  CampoRecolectado('hd_instalada_de_lado', Transformacion.taICual,
      queManda: 'si se instaló con un archivo suelto, sin tienda de por medio',
      paraQue: 'Antifraude: instalada con un archivo suelto, sin tienda — patrón de fraude o de aparato manipulado.',
      computada: true),
  CampoRecolectado('hd_horas_desde_el_arranque', Transformacion.tramo, tramoDe: 24,
      queManda: 'hace cuántas horas se encendió el teléfono, por días',
      paraQue: 'Antifraude: una granja reinicia sus aparatos todo el tiempo; el teléfono de alguien lleva días prendido.'),
  CampoRecolectado('hd_teclados', Transformacion.taICual,
      queManda: 'cuántos teclados tiene configurados. No se manda cuáles',
      paraQue: 'Comportamiento: cuántos teclados tiene, pista de un teléfono en uso real. No se lee cuál.'),

  // ── Canales alcanzables (prueba de concepto) ──────────────────────────────────────────
  CampoRecolectado('canal_whatsapp', Transformacion.taICual,
      queManda: 'si tiene WhatsApp instalado',
      paraQue: 'Alcance: permite mandarle por WhatsApp si el push no llega. Sólo instalado, no si lo usa.',
      computada: true),
  CampoRecolectado('canal_whatsapp_business', Transformacion.taICual,
      queManda: 'si tiene WhatsApp Business instalado',
      paraQue: 'Alcance: un canal de contacto más; suele indicar un comercio o emprendedor.',
      computada: true),
  CampoRecolectado('canal_telegram', Transformacion.taICual,
      queManda: 'si tiene Telegram instalado',
      paraQue: 'Alcance: canal alternativo de mensajería.',
      computada: true),
  CampoRecolectado('canal_messenger', Transformacion.taICual,
      queManda: 'si tiene Facebook Messenger instalado',
      paraQue: 'Alcance: otro canal de mensajería directo.',
      computada: true),
  CampoRecolectado('canal_facebook', Transformacion.taICual,
      queManda: 'si tiene Facebook instalado',
      paraQue: 'Alcance y perfil: presencia en la red; canal para campañas.',
      computada: true),
  CampoRecolectado('canal_instagram', Transformacion.taICual,
      queManda: 'si tiene Instagram instalado',
      paraQue: 'Alcance y perfil: presencia en la red; público más joven.',
      computada: true),
  CampoRecolectado('canal_signal', Transformacion.taICual,
      queManda: 'si tiene Signal instalado',
      paraQue: 'Perfil: quien usa Signal cuida su privacidad; dato de segmentación.',
      computada: true),
  CampoRecolectado('canal_sms_rcs', Transformacion.taICual,
      queManda: 'si tiene la app de Mensajes de Google (SMS/RCS)',
      paraQue: 'Alcance: confirma que el canal de mensajes de texto está disponible.',
      computada: true),
  CampoRecolectado('canal_gmail', Transformacion.taICual,
      queManda: 'si tiene Gmail instalado',
      paraQue: 'Alcance: canal de correo disponible en el teléfono.',
      computada: true),

  // ── Vida económica: qué apps tiene, sin pedir un permiso ──────────────────────────────
  //
  // Pedido de Juan, 2026-09-05: *«no me preguntás si tiene WhatsApp… si tiene Google Maps,
  // qué tanto se mueve»*. Las de arriba existen para saber POR DÓNDE mandarle un mensaje;
  // éstas, para saber algo de la persona.
  //
  // 🔴 Y la trampa del negocio, escrita acá para que no se olvide: tener un teléfono con
  // pocas apps NO es riesgo de crédito, es pobreza. Estas señales sirven si conservan poder
  // predictivo **controlando por nivel de ingreso**; si no lo conservan, se sacan aunque
  // mejoren el número.
  CampoRecolectado('app_mapas', Transformacion.taICual,
      queManda: 'si tiene Google Maps instalado',
      paraQue: 'Puntaje: se mueve y se orienta con el teléfono. Es la base de «cuánto se mueve».',
      computada: true),
  CampoRecolectado('app_viajes', Transformacion.taICual,
      queManda: 'si tiene una app de viajes instalada',
      paraQue: 'Puntaje: paga traslados desde el teléfono, con un medio de pago cargado.',
      computada: true),
  CampoRecolectado('app_mercadolibre', Transformacion.taICual,
      queManda: 'si tiene Mercado Libre instalado',
      paraQue: 'Puntaje: compra por internet, lo que supone una dirección y un medio de pago.',
      computada: true),
  CampoRecolectado('app_mercadopago', Transformacion.taICual,
      queManda: 'si tiene Mercado Pago instalado',
      paraQue: 'Puntaje: mueve dinero digital. Es la señal económica más directa de esta familia.',
      computada: true),
  CampoRecolectado('app_binance', Transformacion.taICual,
      queManda: 'si tiene Binance instalado',
      paraQue: 'Puntaje: en Venezuela es una forma corriente de tener y mover divisas.',
      computada: true),
  CampoRecolectado('app_zelle', Transformacion.taICual,
      queManda: 'si tiene Zelle instalado',
      paraQue: 'Puntaje: recibe o manda dinero en dólares, casi siempre desde el exterior.',
      computada: true),
  CampoRecolectado('app_netflix', Transformacion.taICual,
      queManda: 'si tiene Netflix instalado',
      paraQue: 'Puntaje: paga una suscripción todos los meses, que es capacidad de pago sostenida.',
      computada: true),
  CampoRecolectado('app_spotify', Transformacion.taICual,
      queManda: 'si tiene Spotify instalado',
      paraQue: 'Puntaje: otra suscripción mensual; sumada a la anterior, un hábito de pago recurrente.',
      computada: true),

  // ── Entregabilidad (¿el push va a llegar y lo va a ver?) ──────────────────────────────
  CampoRecolectado('ent_avisos_permitidos', Transformacion.taICual,
      queManda: 'si el sistema permite mostrarle avisos a esta app',
      paraQue: 'Entregabilidad: el permiso general. Si está en no, ningún push se muestra.'),
  CampoRecolectado('ent_canales_silenciados', Transformacion.taICual,
      queManda: 'cuántos de nuestros canales de aviso están en silencio total',
      paraQue: 'Entregabilidad: un sí general con un canal apagado hace que ESE aviso no suene.',
      computada: true),
  CampoRecolectado('ent_exento_de_doze', Transformacion.taICual,
      queManda: 'si la app está exenta de la optimización de batería (Doze)',
      paraQue: 'Entregabilidad clave: si NO está exenta, el push se demora con la pantalla apagada.'),
  CampoRecolectado('ent_restringida_en_segundo_plano', Transformacion.taICual,
      queManda: 'si el sistema restringió la app en segundo plano',
      paraQue: 'Entregabilidad clave: si está restringida, el push directamente no llega.'),
  CampoRecolectado('ent_ahorro_de_bateria', Transformacion.taICual,
      queManda: 'si el ahorro de batería del teléfono está activo',
      paraQue: 'Entregabilidad: el ahorro de batería demora la entrega de los avisos.'),
  CampoRecolectado('ent_modo_no_molestar', Transformacion.taICual,
      queManda: 'el modo No molestar: 1 todo, 2 prioridad, 3 nada, 4 alarmas',
      paraQue: 'Entregabilidad: en No molestar el aviso llega pero no suena ni se ve.'),
  CampoRecolectado('ent_pantalla_encendida', Transformacion.taICual,
      queManda: 'si la pantalla está encendida en este momento',
      paraQue: 'Actividad y momento: la señal más directa de que la persona está usando el teléfono.'),
  CampoRecolectado('ent_nivel_de_senal', Transformacion.taICual,
      queManda: 'el nivel de señal de la antena, de 0 a 4',
      paraQue: 'Señal: con señal baja el push por datos se demora o no llega. Sin permiso desde Android 9.'),
];
