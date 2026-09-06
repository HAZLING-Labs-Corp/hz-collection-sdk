# hz_collection_sdk

Recolectar datos del aparato y recibir notificaciones push, con una llave y una línea.

> **Si venías del manual anterior:** este SDK dejaba de ser sólo de push. Los avisos son ahora
> **uno de cinco módulos**, y cuáles corren lo decide el comercio desde la consola, no tu
> código. Ver [Los módulos](#los-módulos-el-sdk-ya-no-es-sólo-avisos).

```yaml
dependencies:
  hz_collection_sdk: ^0.1.0
```

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AkPush.init(
    llave: 'pk_live_…',              // la llave con alcance devices:write
    url:   'https://…/api/v1',
  );
  runApp(const MiApp());
}
```

**Dos valores.** El comercio no se configura: **sale de la llave**, del lado del
servicio. Pedírtelo aparte sería pedirte un dato que el sistema ya sabe, con el
único efecto de que alguien lo escriba distinto.

Si querés saber contra cuál estás trabajando, la configuración lo dice:

```dart
AkPush.comercio   // 'acme'
```

⚠️ Así como está, `init()` le pide el permiso de notificaciones a la persona en
el arranque. **Casi siempre conviene lo contrario.** Antes de publicar, leé
[El permiso](#el-permiso): es la decisión que más plata cuesta equivocar.

Cuando la persona inicia sesión:

```dart
final r = await AkPush.alIniciarSesion(userId: 'u_123');

if (!r.puedeRecibir) {
  // r.motivo dice por qué, y r.accionSugerida qué hacer al respecto
}
```

⚠️ `init()` es asíncrono. No ofrezcas el botón de inicio de sesión hasta que
resuelva, o vas a recibir `notInitialized`.

Cuando cierra sesión:

```dart
await AkPush.alCerrarSesion();
```

Eso es todo. **No pegás ningún archivo de configuración en el proyecto** — ni
`google-services.json`, ni `GoogleService-Info.plist`. La cuenta de Google la sirve nuestro
servidor en cada arranque, y por eso se le puede cambiar la cuenta a un comercio sin que
publiques una versión nueva.

Con esas dos líneas ya corren también los módulos que el comercio tenga activos: las señales
del aparato, la autenticidad y —si lo activó— la ubicación, que el SDK ofrece con su propia
pantalla.

---

## Iniciar sesión hace más que registrar

`alIniciarSesion()` es la puerta por la que el teléfono queda en orden para esa
persona. Adentro, en este orden:

1. **Si había otra persona en este teléfono, la da de baja.** Antes de tocar nada
   más: si el registro nuevo falla a mitad, el teléfono queda sin dueño y no con
   el anterior, que seguiría recibiendo lo suyo.
2. **Le pregunta al sistema operativo por el permiso.** No confía en lo que tenía
   guardado: la persona pudo haberlo apagado desde los Ajustes hace seis meses y
   nada te avisó.
3. **Decide qué hacer** según lo que configuró tu comercio.
4. **Registra sólo si algo cambió.**

Y te devuelve el resumen:

```dart
r.puedeRecibir        // ¿le va a llegar o no? — casi siempre alcanza con esto
r.estadoDelPermiso    // los cinco estados
r.accionSugerida      // qué te toca hacer AHORA
r.huboCambioDePersona // había otra y se le dio de baja
r.motivo              // la frase que explica por qué no puede recibir
```

`r.motivo` es para tu registro o para un ticket. **No para mostrárselo a la
persona**: eso lo escribís vos, con tu voz.

---

## Lo que configura tu comercio, sin que publiques nada

Cuándo pedir el permiso no lo decide tu código: lo decide tu comercio desde la
consola, y viaja con la configuración.

```dart
AkPush.politica.momento             // arranque · login · laAppDecide
AkPush.politica.obligatorio         // lo considera indispensable
AkPush.politica.preguntaBlanda      // si mostrás tu pantalla antes
AkPush.politica.reintentarCadaDias
AkPush.politica.textos              // titulo · cuerpo · aceptar · ahoraNo
```

Los textos son de tu comercio y hablan con su voz — por eso viajan, en vez de
estar escritos en el paquete.

> **«Obligatorio» no puede significar lo que suena.** Ningún SDK puede forzar a
> nadie a aceptar notificaciones: el diálogo es del sistema operativo y la
> respuesta es de la persona. Significa que tu comercio lo considera
> indispensable, para que tu app insista. Qué hacés con esa señal es tuyo.

Mientras el servicio no sirva la política, podés declararla vos:

```dart
await AkPush.init(
  llave: '…',
  politicaPorDefecto: const PoliticaDeNotificaciones(
    momento: MomentoDelPermiso.login,
    preguntaBlanda: true,
  ),
);
```

Cuando el servicio la mande, gana la del servidor.

---

## Los módulos: el SDK ya no es sólo avisos

Cada cosa que el SDK mide es un **módulo**, y **el comercio decide cuáles corren** desde la
consola. Tu código no los prende ni los apaga: llegan resueltos en la configuración.

```dart
AkPush.modulos          // {'avisos': …, 'senales': …, 'ubicacion': …}
AkPush.modulos['senales']?.estado    // 'activo' · 'declarado'
```

| Módulo | Qué mide | Permiso | Nace |
|---|---|---|---|
| `avisos` | la dirección para notificar, y qué se hizo con cada aviso | notificaciones | prendido |
| `autenticidad` | si es un teléfono de verdad o un emulador | ninguno | prendido |
| `senales` | ~90 propiedades del aparato — ver abajo | **ninguno** | apagado |
| `ubicacion` | la zona, no la dirección exacta | ubicación | apagado |
| `rastreo` | ubicación en segundo plano | ubicación de fondo | apagado |

`declarado` no es `activo`: significa que el módulo existe pero **este comercio no lo puede
usar**, porque su rubro no lo permite. Un comercio de préstamo personal no rastrea a nadie
aunque prenda el interruptor.

🔴 **Nada de esto lo decidís vos, y es a propósito.** Si un comercio pudiera activar la
recolección desde el código de su app, la consola dejaría de ser la fuente de verdad de qué se
recolecta — y eso es justamente lo que hay que poder mostrarle a un auditor.

---

## Las señales, y por qué hay que contarlas

`senales` mide propiedades del aparato **sin pedir un solo permiso**: configuración, batería,
sensores, red, y la huella —idioma, zona horaria, modelo, hora local—. Ninguna dice quién es la
persona; dicen cómo está configurado el teléfono y si se comporta como uno de verdad.

🔴 **ANDROID MIDE ~90 CAMPOS. iOS MIDE 33. Y ESA DIFERENCIA NO SE DISIMULA.**

Medido el 2026-09-01 con la misma app en las dos plataformas: 88 campos en Android, 33 en
iPhone. No es un error ni algo que se vaya a emparejar: en iOS **no existen** la configuración
del sistema (`cfg_`), la enumeración de servicios de accesibilidad (`acc_`) ni el multiusuario
(`usr_`). Apple no los expone.

**Lo que no se puede medir no viaja.** No se rellena con ceros. Y eso es una decisión, no un
descuido: un cero diría «se midió y dio cero», que es distinto de «no se pudo medir». Si se
rellenara, un puntaje trataría a todos los iPhone como el mismo teléfono raro — y peor, creería
que la señal de control remoto se midió y salió negativa, cuando nunca se midió.

> **Quien consuma estos datos tiene que mirar CUÁNTOS campos llegaron antes de interpretarlos.**
> Comparar un aparato de 88 campos con uno de 33 como si fueran lo mismo es la forma más fácil
> de sacar una conclusión falsa con datos correctos.

Y ojo con un caso más: en un **simulador** los sensores llegan en `false` y la red en `0` porque
de verdad no existen, no porque el teléfono sea raro. `autenticidad` lo dice aparte:

```dart
// esFisico: false · pareceEmulador: true
```

---

## El comportamiento dentro de tu propia aplicación

Es lo que pasa **en tu pantalla**: a qué hora abre la persona, cuánto tarda en llenar la
solicitud, cuántas veces la abandona y vuelve, y si pega la cédula o la escribe.

🔴 **No pide un solo permiso, y no puede pedirlo: no hay nada que pedir.** No se está leyendo
nada de nadie más — es tu aplicación, tu formulario y tu campo de texto. Es la mitad más valiosa
del colector para quien presta plata, porque es justo lo que quedó del otro lado de la puerta
que Google cerró en 2019 con los SMS y el registro de llamadas.

### 🔴 Lo que NUNCA se captura, y es un límite duro

**El contenido de lo que la persona escribe.** Se mide *que pegó la cédula*, nunca *qué cédula
pegó*. Se mide *cuánto tardó*, nunca *qué escribió*. En concreto, y para que no haya que
adivinarlo:

| lo que se captura | lo que **no** se captura |
|---|---|
| que el campo se llenó de un golpe (pegado) o tecleando | el texto, entero o en pedazos |
| cuántas veces lo corrigió | el **largo** de lo que escribió |
| cuánto tardó, en milisegundos | un hash del contenido — un hash de una cédula *es* una cédula |
| el **nombre** del campo, que lo ponés vos (`cedula`) | lo que la persona puso adentro |

Hay una prueba que lo comprueba escribiendo y pegando una cédula de verdad y buscando cualquier
pedazo de ella en todo lo que el SDK guardaría: `test/comportamiento_test.dart`.

### Cinco líneas y el formulario queda medido

```dart
class _SolicitudState extends State<Solicitud> {
  final f = AkPush.formulario('solicitud');   // ① se declara

  @override void initState() { super.initState(); f.abrir(); }   // ② entró
  @override void dispose()   { f.dispose(); super.dispose(); }   // ⑤ se fue

  @override Widget build(_) => Column(children: [
    TextField(                                                    // ③ un campo
      controller: f.campo('cedula').controlador,
      focusNode:  f.campo('cedula').foco,
    ),
    FilledButton(onPressed: () => f.enviar(), child: Text('Enviar')),  // ④ lo mandó
  ]);
}
```

El SDK **no puede adivinar** qué pantalla es «la solicitud» ni cuál de los botones la envía: por
eso se declara. La sesión —abrir, cerrar, cuánto duró— sí sale sola, del ciclo de vida.

Los siete tipos de evento son fijos y los comparte con el servicio:
`SESION_ABRE · SESION_CIERRA · FORMULARIO_ABRE · FORMULARIO_ENVIA · FORMULARIO_ABANDONA ·
CAMPO_PEGADO · CAMPO_ESCRITO`.

> **Cómo se sabe que pegó sin leer lo que pegó:** mirando el largo del texto. Escribir agrega un
> carácter por vez; pegar los agrega todos de golpe. En un campo de texto libre con sugerencias
> del teclado, tocar una sugerencia inserta una palabra entera y se ve igual que un pegado — en
> los campos donde esto importa (cédula, monto, teléfono) el teclado es numérico y no se
> confunde. Para un campo de nombre, la señal es más floja y hay que leerla como tal.

---

## La política de transmisión: qué sale del teléfono, y cuándo

Hasta esta versión el SDK **medía y mandaba en el mismo acto**, siempre. Medido en el emulador el
2026-09-04, contando peticiones: **cinco llamadas por sesión, 3.906 bytes**, de los cuales 3.096
eran dos mediciones que en la segunda sesión decían exactamente lo mismo que en la primera.

Ahora hay cinco decisiones, y ninguna hay que configurar:

| | qué hace | el número |
|---|---|---|
| **cuándo se mide** | al abrir la aplicación | igual que antes |
| **cuándo se transmite** | 🔴 nunca en el momento de medir — se guarda y sale **por lote, al abrir** | 1 llamada por apertura |
| **qué dispara un envío** | sólo un cambio real | 10 señales de momento no cuentan |
| **sin conexión** | se acumula y se descarta lo más viejo | 1.000 eventos ó 512 KB |
| **resincronización** | se manda todo igual aunque nada haya cambiado | cada 7 días |

Después: **cuatro llamadas por sesión y 1.011 bytes** — y una de esas cuatro es el lote de
comportamiento, que antes no existía. Las mediciones de señales pasaron de 2 por sesión a 0
cuando el teléfono no cambió, y vuelven a salir en cuanto cambia algo de verdad.

### 🔴 La trampa de las señales de momento

De las 105 señales, **diez cambian en cada medición**: la hora local, el día de la semana, si la
pantalla está encendida, el nivel de señal, la temperatura y el voltaje de la batería, la
velocidad de bajada y de subida, las veces que se encendió el teléfono, y la marca de tiempo de
la ubicación. Si contaran como cambio, el delta nunca estaría vacío y «mandá sólo lo que cambió»
mandaría **siempre todo**. El sistema parecería andar bien; sólo sería caro — y no daría ningún
síntoma hasta la factura.

Están declaradas en `senalesDeMomento`, y una prueba fija los diez nombres para que nadie los
cambie de un solo lado: el servicio tiene la misma lista.

📌 **Y hay dos más, encontrados midiendo el 2026-09-04:** `hd_ram_libre_mb` y
`hd_ram_en_las_ultimas`. Con el delta ya andando, una sesión sin tocar nada seguía
transmitiendo las 105 señales enteras — la pantalla lo dijo con todas las letras: *«senales:
cambiaron 1 campos: hd_ram_libre_mb»*. **Un solo campo alcanzaba para anular el mecanismo
entero.** Que son momentos lo dicen sus propias fichas: «cuánta memoria tenía libre *al
medir*». Viven en `momentosQueElBackTodaviaNoTiene`, aparte y no mezclados con los diez, hasta
que el servicio los agregue de su lado.

### Volver al comportamiento de antes, en una línea

```dart
await AkPush.init(
  llave: '…',
  politicaDeTransmision: PoliticaDeTransmision.comoEstabaAntes,  // mide y manda siempre
);
```

### Ver qué está haciendo

```dart
final e = await AkPush.estadoDelComportamiento();
// comportamiento: midiendo · 6 en cola · último envío: 4 eventos

AkPush.ultimasDecisiones;
// {senales: cambiaron 2 campos: cfg_font_scale, cfg_screen_off_timeout,
//  autenticidad: nada cambió desde la última vez (los momentos no cuentan)}

await AkPush.transmitirComportamiento();   // 🔴 la excepción, no el camino
```

`transmitirComportamiento()` existe para el caso en que necesitás el dato **en el momento** —
recién enviada una solicitud, con un analista esperando del otro lado—. Llamarla por cada evento
devuelve el SDK a lo que hacía antes de que existiera la política, y con más pasos.

### Nada de esto puede impedir que tu aplicación abra

Si no hay red, si la cola está llena, si el almacenamiento del teléfono falla: **la aplicación
abre igual**. Todo el módulo está envuelto y no propaga nada hacia arriba. Una medición perdida
es un problema; una aplicación que no abre es otro tamaño de problema.

---

## Cuando el comercio no tiene Firebase configurado

**El SDK arranca igual y recolecta igual.** Desde el 2026-09-01, que le falte la configuración
de Firebase —o que el paquete de tu app no esté registrado en el comercio— ya no tumba el
arranque: se dan de alta la instalación y los módulos, y **sólo los avisos quedan apagados**.

```dart
AkPush.sinAvisosPorque    // null si los avisos están en pie
```

Antes, un paquete sin registrar apagaba **todo**: ni señales, ni ubicación, ni autenticidad —
cosas que no tienen nada que ver con notificar. Se separó porque recolectar y notificar son dos
trabajos distintos.

🔴 **Y por eso hay que mirar ese campo.** Es el estado más engañoso que tiene el SDK: la app
arranca, los datos llegan, la consola se ve viva, y los avisos no salen. Sin preguntar por qué,
la única forma de enterarse es que alguien note que hace días que no le llega nada.

---

## Marcá lo que contestó en tu modal

Si mostrás la pregunta blanda, avisale al SDK qué contestó — **en los dos casos,
no sólo cuando acepta**:

```dart
final si = await mostrarMiPantalla();
await AkPush.reportarModal(acepto: si);
if (si) await AkPush.pedirPermiso();
```

Un «ahora no» también es un dato, y es el que distingue a quien se puede
recuperar de quien ya dijo que no de verdad.

### Por qué importa: son dos preguntas, no una

| | quién la levanta | si dice que no |
|---|---|---|
| tu modal | **tu app** | no cuesta nada · se le vuelve a preguntar |
| el diálogo | **el sistema operativo** | en iPhone, definitivo |

Alguien puede decir **que sí al tuyo y que no al del sistema**. Sin marcarlo, esa
persona queda igual que quien nunca vio nada — siendo situaciones opuestas.

```dart
AkPush.consentimiento.punto
// sin_preguntar · dijo_ahora_no · esperando_al_sistema
// acepto · denego_en_el_sistema
```

---

## Lo único que tenés que darnos

**El identificador de tu aplicación** — `com.tuempresa.app` en Android, el *bundle
id* en iOS. Lo necesitamos para registrarla y para verificar que la configuración
que te entregamos sirve para tu aplicación y no para otra.

Es lo único. No hay más.

---

## Lo que sí queda en tu compilación

Dos cosas no se pueden mover a tiempo de ejecución, y las tenés resueltas si tu
app ya está publicada:

| | |
|---|---|
| El identificador del paquete | Se fija al compilar. Si la app ya está publicada, no se puede cambiar |
| Recibir notificaciones en iPhone | Es una capacidad que se activa al compilar, con tu perfil de Apple |

### Android

**1 · Habilitar *core library desugaring*.** Lo exige la librería que dibuja el
aviso cuando tu app está abierta. Sin esto la compilación falla con
`requires core library desugaring to be enabled`.

En `android/app/build.gradle.kts`:

```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

**2 · El canal por defecto.** En `AndroidManifest.xml`, dentro de `<application>`:

```xml
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="default" />
```

Sin eso, los avisos que llegan con la app cerrada caen en un canal que no existe.

**3 · El permiso**, en Android 13 y superiores:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

### iOS

Desde el 2026-09-01 el SDK **tiene lado nativo de iOS** (`ios/Classes/SenalesPlugin.swift`) y
mide 33 señales. Antes devolvía un mapa vacío y nadie se enteraba.

**1 · Capacidades en Xcode:** activar *Push Notifications*. Y si tu comercio usa avisos en
segundo plano, *Background Modes → Remote notifications*.

**2 · Textos de permiso en `Info.plist`.** Sin el texto, iOS **no muestra el diálogo**: lo
niega en silencio, y el síntoma es que el permiso «no se pudo pedir» sin ninguna causa visible.

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Para avisarte de operaciones que no reconozcas y mostrarte la oficina más cercana.</string>
```

Ese texto lo lee la persona en el diálogo del sistema: escribilo con la voz de tu comercio.

**3 · 🔴 La llave de APNs, que no existe en Android.** Para que un push llegue a un iPhone,
Firebase necesita una llave de APNs de tu cuenta de Apple, cargada en la consola de Firebase.
**Sin ella el envío se acepta, queda registrado como enviado, y no llega.** No hay error en
ningún lado. Es el candidato número uno a «el push no llega y no sé por qué».

La llave es del **equipo de Apple**, no de la app: una sola sirve para todas tus apps de iOS.
Apple permite un máximo de dos por cuenta, y el archivo `.p8` **se descarga una sola vez**.

**Lo que el SDK deliberadamente NO mide en iOS**, aunque podría: la lista de teclados
instalados y el tiempo desde el arranque. Las dos son *Required Reason APIs* de Apple y
obligan a declarar un motivo aprobado en la ficha de privacidad. No valen lo que cuestan.

**Y una diferencia de comportamiento que conviene tener a la vista:** el módulo de ubicación
pide precisión aproximada, y **Android la respeta y iOS no**. Medido: Android devolvió 2000 m,
iPhone devolvió 5 m con la misma configuración. iOS no tiene un permiso «sólo aproximado»
equivalente. Si tu pantalla le promete a la persona «es la zona, no la dirección exacta»,
en iPhone hoy esa promesa se cumple a medias.

---

## El permiso

Un push no llega si la persona no dijo que sí. El que pregunta es el sistema
operativo, con un diálogo suyo. Tu aplicación no lo dibuja, no lo cambia y no lo
puede repetir.

**Ese diálogo se gasta.** Se muestra una vez y no vuelve.

### Por defecto se pide en el arranque, y eso casi nunca conviene

`init()` viene con `pedirPermisoAlIniciar: true`, porque es lo que este paquete
hacía desde la primera versión. Así, el diálogo salta apenas la persona abre la
aplicación por primera vez.

Es el peor momento posible. Todavía no sabe qué hace tu aplicación. No tiene con
qué contestar. Y el «no» que se lleva ahí no se recupera nunca más.

### Cuánto dura un «no»

| | |
|---|---|
| iPhone | El diálogo se muestra **una sola vez en la vida de la instalación**. Después, solo los Ajustes del teléfono |
| Android 13 y superiores | Alcanzan **dos descartes** para que el sistema lo dé por denegado y no lo muestre más |
| Android 12 y anteriores | No hay diálogo. Los avisos vienen encendidos de fábrica; si la persona los apaga, solo los Ajustes los vuelven a encender |

A los Ajustes no va casi nadie. En los hechos, un «no» es para siempre.

### La pregunta blanda

Primero mostrás **una pantalla tuya**. Tu marca, tus palabras, en el momento en
que el aviso ya se entiende: después de la primera compra, cuando queda un pago
por vencer, al terminar el alta.

Y solo si ahí la persona dice que sí, disparás el diálogo del sistema.

Eso convierte un «no» irreversible en un «ahora no». Quien dice que no en tu
pantalla se lo podés volver a ofrecer la semana que viene: el diálogo del sistema
sigue entero. Quien dice que no en el diálogo del sistema no vuelve.

**Esa pantalla la escribís vos.** El paquete no la trae, y no debería: es tuya.

### El camino recomendado

Al arrancar, no pidas nada. `init()` solo lee lo que ya haya:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AkPush.init(llave: 'pk_live_…', pedirPermisoAlIniciar: false);
  runApp(const MiApp());
}
```

Y cuando el aviso ya tiene sentido para la persona, ofrecelo:

```dart
Future<void> ofrecerAvisos(BuildContext context) async {
  final estado = await AkPush.estadoDelPermiso();

  // Ya recibe. No hay nada que ofrecer.
  if (estado.permiteRecibir) return;

  // El diálogo del sistema ya no existe. Solo quedan los Ajustes.
  if (estado.soloQuedanLosAjustes) {
    if (await miPantallaQueMandaALosAjustes(context)) {
      await AkPush.abrirAjustesDeNotificaciones();
    }
    return;
  }

  // Queda diálogo: primero tu pantalla, y el diálogo solo si dice que sí.
  if (estado.puedeVolverAPreguntarse) {
    if (await miPantallaQueExplica(context)) {
      await AkPush.pedirPermiso();
    }
  }
}

// Las dos son tuyas. Devuelven `true` si la persona apretó el botón de aceptar.
Future<bool> miPantallaQueExplica(BuildContext context) async => ...;
Future<bool> miPantallaQueMandaALosAjustes(BuildContext context) async => ...;
```

`estadoDelPermiso()` **no dispara ningún diálogo**: se puede llamar todas las
veces que haga falta. `pedirPermiso()` sí — es la línea que gasta el diálogo, y
por eso es la única que va detrás de un «sí» de la persona.

Las dos se llaman después de `init()`.

### Los cinco estados

| `EstadoDelPermiso` | qué pasó | qué hacer |
|---|---|---|
| `sinPreguntar` | Nadie preguntó todavía. El diálogo está entero | La pregunta blanda |
| `concedido` | Hay permiso. Los avisos llegan y se ven | Nada |
| `denegado` | Dijo que no, pero queda un diálogo más. En los hechos, solo en Android 13+ | La pregunta blanda. Es la última |
| `denegadoParaSiempre` | Dijo que no y el diálogo no se muestra más | Los Ajustes |
| `provisional` | iOS: los avisos entran al centro de notificaciones en silencio, sin interrumpir | Se puede ofrecer pasar a avisos que sí interrumpen |

Y tres preguntas, para no ramificar sobre los cinco:

| | |
|---|---|
| `permiteRecibir` | Si con este estado el teléfono recibe avisos. `provisional` cuenta |
| `puedeVolverAPreguntarse` | Si mostrar tu pantalla sirve de algo, o termina en un botón que no puede hacer nada |
| `soloQuedanLosAjustes` | Si la única puerta que queda es la del teléfono |

No son opuestas. `concedido` recibe y no admite diálogo; `denegadoParaSiempre` no
recibe y tampoco lo admite.

### Volvé a leer el estado cuando la app vuelve del segundo plano

El permiso se cambia desde los Ajustes del teléfono, y **nada le avisa a tu
aplicación** cuando eso pasa.

Releerlo no es solo mirar: si la persona activó los avisos, esa misma llamada
consigue la dirección del teléfono y lo vuelve a dar de alta sola. Sin eso, hay
permiso y no llega nada.

```dart
class _MiAppState extends State<MiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) AkPush.estadoDelPermiso();
  }
}
```

### Cuando ya está denegado para siempre

Queda una sola puerta:

```dart
final abrio = await AkPush.abrirAjustesDeNotificaciones();
```

Devuelve si se pudo abrir la pantalla. **No** si la persona activó algo — eso no
se puede saber desde la app. Se sabe al volver, releyendo el estado.

Abre la ficha de tu aplicación y no la pantalla exacta de notificaciones: no hay
forma de llegar directo en las dos plataformas. Desde la ficha están a un toque.

⚠️ No muestres acá una pantalla que prometa activar los avisos con un botón. El
botón no puede hacer nada: `pedirPermiso()` en este estado no muestra ningún
diálogo y devuelve lo mismo que había.

### Sin permiso no hay dirección

Sin permiso el teléfono no tiene dirección a la cual enviarle. En iPhone es
literal: el sistema no la emite hasta que la persona dice que sí.

`identify()` funciona igual — guarda a la persona y no falla. El alta al servidor
sale sola en cuanto haya permiso. No hace falta acordarse de llamarlo de nuevo.

---

## Escuchar lo que llega

```dart
AkPush.onMessage.listen((m) {
  // Llegó con la app abierta. Ya lo dibujamos nosotros:
  // FCM no dibuja nada en primer plano.
});

AkPush.onNotificationTap.listen((m) {
  // La persona lo tocó. Venga de donde venga:
  // app abierta, en segundo plano o cerrada.
  final codigo = m.codeEvent;
});
```

`PushMessage` trae `title`, `body` y `data`, más tres atajos: `pushLogId`
(el envío), `codeEvent` (el aviso) y `signal` (los avisos que solo te dicen «andá
a revisar algo»).

La entrega y la apertura las contamos nosotros —también cuando el aviso llega
con la app cerrada o en segundo plano, que es el caso normal—. Las otras tres
acciones dependen de cómo esté hecha tu app, así que las reportás vos:

```dart
await AkPush.reportar(mensaje, AccionDePush.viewed);      // lo vio sin abrirlo
await AkPush.reportar(mensaje, AccionDePush.dismissed);   // lo descartó
await AkPush.reportar(mensaje, AccionDePush.expired);     // caducó
```

> **La tasa de entrega es una cota inferior, no un número exacto.** Para acusar
> recibo con la app cerrada, el sistema operativo tiene que despertarla, y no
> siempre lo hace: en iOS el envío necesita `content-available`, y tanto Android
> como iOS se reservan el derecho de no despertar una app que el usuario no
> abre nunca o que tiene la batería baja. Lo que ves entregado, llegó. Lo que
> ves sin entregar puede haber llegado igual.

---

## Cuándo dibujar el aviso, y cuándo no

Con la app abierta, el aviso lo dibujamos nosotros. Vos podés opinar sobre cada
uno, porque el único que sabe si molesta es quien escribió la pantalla.

El caso típico: la persona está mirando el detalle de la compra 9912 y llega
«tu compra 9912 fue aprobada». Dibujarlo le tapa con una tarjeta lo mismo que
tiene delante de los ojos.

```dart
AkPush.alDecidirDibujo = (m) {
  if (_pantallaActual == '/compras/${m.data['ruta_id']}') {
    return DecisionDeDibujo.noMostrar;
  }
  return DecisionDeDibujo.mostrarSilencioso;
};
```

| `DecisionDeDibujo` | |
|---|---|
| `mostrar` | Como siempre: visible, con sonido y vibración |
| `mostrarSilencioso` | Visible, sin sonido ni vibración. Para cuando la persona está en la app y lo va a ver igual |
| `noMostrar` | No se dibuja nada |

### La medición ocurre igual

**La decisión afecta únicamente al dibujo.** El aviso se sigue contando como
entregado y `onMessage` se sigue emitiendo, incluso con `noMostrar`.

Es a propósito: el aviso **llegó al teléfono**. Que tu app haya decidido no
dibujarlo es una decisión tuya, posterior a la entrega. Si no lo contáramos, tu
tasa de entrega bajaría cada vez que tu app decide ser prolija — y quien mire el
tablero va a concluir que se están perdiendo envíos que en realidad llegaron
todos. Peor: el comercio que más cuida a su gente sería el que peor mide.

Y `onMessage` sigue emitiendo porque es por donde reaccionás al contenido —
refrescar un saldo, poner un punto rojo en el menú. Silenciar el aviso no es
ignorar lo que traía adentro.

### Tres detalles

- Se puede asignar **antes de `init()`**. No hay nada que lo pise.
- Tenés **150 ms** para contestar. Es corto a propósito: mientras contestás no
  hay nada en la pantalla. Lo único que tiene que hacer es leer algo que tu app
  ya tiene en memoria. Si no te alcanzan, es que estás yendo a la base o a la
  red, y eso acá no va.
- Si tardás de más, o si tu código falla, **se dibuja**. Un aviso de más es una
  molestia de un segundo; uno de menos puede ser el pago que venció.

---

## Llevar el toque a la pantalla correcta

Quién sabe a dónde tiene que ir un aviso es el que lo manda, el día que lo manda.
Por eso el destino viaja en el envío. Cambiar a dónde lleva una campaña deja de
exigir una versión nueva en las tiendas.

### Lo que tiene que mandar tu backend

Dentro del `data` del envío, dos claves y nada más:

```json
{
  "data": {
    "ruta": "/compras/:id",
    "ruta_id": "9912",
    "ruta_tab": "pagos"
  }
}
```

| clave | ¿obligatoria? | |
|---|---|---|
| `ruta` | **sí** | Un camino absoluto, empezando con `/`. Con marcadores `:nombre` o ya resuelto |
| `ruta_<nombre>` | no | El valor del marcador `:nombre`. Texto plano, uno por clave |

Con eso, la app recibe `destino == '/compras/9912'` y
`parametros == {'id': '9912', 'tab': 'pagos'}`.

Cuatro cosas más que conviene saber:

- Mandar la ruta ya resuelta —`"ruta": "/compras/9912"`— es igual de válido y no
  necesita ningún parámetro.
- La ruta puede traer su propia consulta: `"/compras/9912?tab=pagos"` funciona.
  Si el mismo nombre viene por los dos caminos, gana `ruta_<nombre>`.
- **El prefijo `ruta_` no es decorativo.** `data` ya tiene dueño: `pushLogId`,
  `code_event`, `type` y `channelId` los usamos nosotros. Un parámetro tuyo
  llamado `type` rompería la detección de señales sin que nadie se entere.
- Un aviso **sin** `ruta` es lo normal, no un error: la mayoría solo informa.

### Lo que escribís en la app

```dart
class _RaizState extends State<Raiz> {
  late final VoidCallback _cortar;

  @override
  void initState() {
    super.initState();
    _cortar = AkPush.alRutear((ruta) => _navegador.go(ruta.destino));
  }

  @override
  void dispose() {
    _cortar();
    super.dispose();
  }
}
```

Una línea cubre los dos casos, que son distintos y los dos existen:

- **El toque en frío**, con la app muerta. El sistema la arranca para entregarlo
  y el toque llega antes de que exista tu navegador. La ruta queda guardada y se
  entrega cuando aparecés.
- **El toque en caliente**, con la app abierta. Llega y se entrega.

La ruta se entrega **una sola vez**. Una intención que se puede leer dos veces se
navega dos veces, y la persona termina viendo cómo se le vuelve a abrir algo que
ya cerró.

⚠️ Llamar a la función que devuelve `alRutear()` en `dispose()` no es opcional.
Un consumidor muerto que siga suscrito se lleva la ruta que le tocaba al vivo.

Si preferís manejarlo a mano, `AkPush.consumirRuta()` la devuelve y la limpia, y
`AkPush.rutaPendiente` es un `ValueListenable` para mirar sin consumir —sirve
directo con `ValueListenableBuilder`—. También podés preguntarle a cualquier
mensaje: `m.tieneRuta` y `m.ruta`.

### Dos cosas que la ruta no hace

- **No sobrevive al cierre de la app.** Si la persona tocó el aviso y la app se
  cerró antes de llegar a la pantalla, eso se perdió. Entregarla tres días
  después, cuando abre la app para otra cosa, no se lee como una función: se lee
  como un fantasma y se reporta como un error.
- **No sobrevive a `logout()`.** Una ruta guardada apunta a los datos de quien
  estaba usando el teléfono.

---

## Cuando no llegan los push

Es la primera pregunta de toda integración, y tiene respuesta:

```dart
final d = await AkPush.diagnostico();
print(d);
```

```
AkPush — diagnóstico
Qué pasa: Todavía no se le preguntó a la persona si acepta notificaciones, y hasta que diga que sí el sistema no emite ningún token. Pedile el permiso desde una pantalla donde ya se entienda para qué sirve: el diálogo del sistema se muestra una sola vez.
Eslabón roto: permiso

  configuración ok    versión v3 · del servidor · comercio cmr_8812
  firebase      ok    tienda-nube-prod · 1:9912:android:aa11
  permiso       ROTO  sinPreguntar
  token         ROTO  no hay
  registro      ROTO  sin identify()
  último error        ninguno
```

Para que un push llegue tienen que estar bien cinco cosas, en este orden:
configuración, Firebase, permiso, dirección del teléfono y alta en el servidor.
**Desde afuera los cinco fallos se ven igual: no pasa nada.** El diagnóstico dice
cuál de los cinco está cortado y qué hacer, en castellano.

Ponelo detrás de un botón escondido de soporte y pedile la captura al que
reporta. El ticket llega con la respuesta adentro en vez de con una foto de una
pantalla vacía.

| | |
|---|---|
| `d.quePasa` | La frase: qué está roto y qué hacer |
| `d.eslabonRoto` | `configuracion`, `firebase`, `permiso`, `token`, `registro` o `ninguno` |
| `d.todoBien` | Si la cadena está entera |
| `d.toJson()` | Lo mismo, para mandar por telemetría y poder agrupar |

### Por qué es lo primero que hay que mirar

- **Se puede llamar aunque `init()` haya fallado**, que es justo cuando más
  sirve. No tira `notInitialized`.
- **Compara con qué cuenta de Google quedó conectada tu app de verdad** contra la
  que el servidor le asignó al comercio. Ese fallo es el más caro y el más mudo:
  la app arranca, pide su dirección y la consigue, pero es la dirección de otro
  proyecto y ningún envío del comercio la va a alcanzar jamás.
- **Saca a la luz el error que nos tragamos** para no romperte el arranque.
- **Avisa si estás trabajando con la configuración guardada** porque hoy no se
  pudo pedir la del servidor.
- **No toca nada.** No pide permiso, no registra, no envía. Un diagnóstico que
  arregla es un diagnóstico que miente — y pedir el permiso desde un botón de
  «diagnosticar» te quema el diálogo que estabas tratando de medir.

Del token muestra el principio y el fin, no el token entero: alcanza para
comparar dos teléfonos, que es lo único para lo que se mira, y no queda pegado
para siempre en un chat.

Si dice que la cadena está entera y aun así no llegan, el problema no está en el
teléfono: está en el envío. Revisá en el panel si salió y qué contestó el
proveedor.

---

## Lo que podés llamar, todo junto

Referencia corta. Cada una está explicada en su sección.

**Arranque y sesión**

```dart
await AkPush.init(llave: …, url: …, pedirPermisoAlIniciar: false);
await AkPush.alIniciarSesion(userId: 'u_123');
await AkPush.alCerrarSesion();
AkPush.comercio                 // contra qué comercio estás
```

**Avisos**

```dart
await AkPush.estadoDeAvisos();  // cómo están, en lenguaje llano
await AkPush.resolverAvisos();  // el botón que sirva EN ESTE estado
AkPush.campanita();             // el widget con punto rojo y su hoja
AkPush.tienePermiso
AkPush.sinAvisosPorque          // null si están en pie
```

🔴 **`resolverAvisos()` es el que conviene usar, y no `pedirPermiso()`.** Hay tres estados
—el sistema todavía pregunta, ya no pregunta más, o ya están activados— y cada uno necesita
una acción distinta: levantar el diálogo, abrir los Ajustes, o no hacer nada. **Tu app no
tiene que saber en cuál está.** Si llamás al diálogo cuando el sistema ya no lo muestra, la
persona toca «Permitir», no pasa nada, y no hay forma de explicárselo.

**Ubicación**

```dart
await AkPush.ofrecerUbicacion();     // con la pantalla del SDK
AkPush.politicaDeUbicacion
await AkPush.tieneUbicacion;
```

Si tu comercio la configuró en `despuesDeEntrar`, el SDK la ofrece **solo** al iniciar sesión y
no tenés que llamar nada. `ofrecerUbicacion()` es para el otro momento, `laAppDecide`:
ofrecerla cuando sirve para algo —al abrir el mapa de sucursales— que es cuando más gente
acepta.

**Comportamiento en tu aplicación**

```dart
final f = AkPush.formulario('solicitud');   // ver la sección del comportamiento
f.abrir(); f.enviar(); f.abandonar(); f.dispose();
f.campo('cedula').controlador               // el TextEditingController, ya observado
f.campo('cedula').foco                      // el FocusNode, ya observado
await AkPush.estadoDelComportamiento();     // cuántos esperan, cuándo salió el último lote
await AkPush.transmitirComportamiento();    // 🔴 la excepción: el lote sale solo al abrir
AkPush.politicaDeTransmision                // los cinco números
AkPush.ultimasDecisiones                    // por qué se transmitió cada módulo, o por qué no
```

**Módulos y diagnóstico**

```dart
AkPush.modulos                  // qué activó el comercio
await AkPush.diagnostico();     // el informe completo, para pegar en un ticket
```

---

## Errores

Todos son `AkPushError`, con un `code` para ramificar y `retryable` para saber si
esperar sirve.

| `code` | qué pasó | ¿reintentar? |
|---|---|---|
| `unauthorized` | la llave falta o es inválida | no |
| `appMismatch` | el identificador de tu app no es el que registramos | no |
| `firebaseInit` | tu app ya inicializó Firebase con otra cuenta — ver abajo | no |
| `permissionDenied` | la persona no dio permiso. **No es un fallo, es una respuesta** — el permiso se consulta con `estadoDelPermiso()`, no se atrapa como error | no |
| `notInitialized` | llamaste a `identify()` o `logout()` antes de que `init()` terminara | no |
| `firmaDeIdentidad` | tu comercio exige el `userId` firmado, y la firma falta o no coincide | no |
| `rutaNoEncontrada` | la dirección está mal configurada | no |
| `unknown` | algo falló y no se pudo clasificar. El detalle está en `details`, y aparece en el diagnóstico como «último error» | no |
| `network` · `serviceUnavailable` | no hubo respuesta, o el servicio no está | **sí** |

### Sobre `firmaDeIdentidad`

Tu comercio puede exigir que el `userId` venga **firmado**, para que nadie que
descomprima el APK pueda registrarse como otra persona y recibir sus avisos.

La firma es un HMAC del `userId` con un secreto que sólo conocen tu comercio y
el servicio. **La calcula tu backend, nunca la app** — en la app sería tan
legible como la llave.

```dart
// tu backend te devuelve la firma junto con la sesión
final r = await AkPush.alIniciarSesion(
  userId: 'u_8891',
  identityHash: sesion.firmaDePush,
);
```

Si te da este error, no revises la llave: falta que tu backend calcule y mande
la firma.

### Sobre `firebaseInit`

Este paquete **es dueño de la app de Firebase por defecto**, porque el transporte
de notificaciones solo trabaja con esa. Si tu aplicación llama a
`Firebase.initializeApp()` por su cuenta con otra configuración, sacá esa llamada
y dejá que `AkPush.init()` la haga.

---

## Lo que hace solo, sin que le pidas nada

- **Guarda la última configuración.** Solo la primerísima instalación necesita
  señal; de ahí en adelante arranca aunque el teléfono esté sin conexión.
- **Se da cuenta si cambiamos tu cuenta de Google.** Un token de notificaciones
  solo vale dentro de la cuenta que lo emitió: si cambiara y el teléfono no se
  enterara, quedaría mudo para siempre y sin ningún error. El paquete lo detecta,
  descarta la dirección vieja y consigue una nueva.
- **Se vuelve a registrar cuando el sistema rota la dirección del teléfono**, que
  pasa solo.
- **Vuelve a dar de alta el teléfono en cuanto aparece el permiso.** Apenas lee
  que hay permiso —al pedirlo, o al releer el estado— consigue la dirección y
  registra. Es lo que hace que pedir el permiso tarde no cueste nada.
- **Dibuja el aviso cuando tu app está abierta**, que es lo que el transporte no
  hace, y crea los canales de Android.
- **No abre el mismo aviso dos veces.** Con la app cerrada, el sistema reporta el
  toque por dos caminos distintos.
- **Guarda la ruta del último toque** hasta que exista alguien capaz de navegar,
  y la tira al cerrar sesión.

---

## Estado

Versión `0.1.0`, en prueba de concepto. Android probado de punta a punta contra
un servicio real; iOS todavía no.

**Lo que hace hoy:** configuración servida por el servidor, permiso diferido con
pregunta blanda, el ciclo de sesión completo, el rastro del consentimiento, los
tres caminos de llegada, el control del dibujo, el ruteo del toque, el
diagnóstico, y la baja al cerrar sesión.

**Lo que todavía no:**

| | |
|---|---|
| **La entrega en segundo plano no se cuenta** | Los avisos que llegan con tu app cerrada se ven y se pueden tocar, pero su *entrega* no entra en las estadísticas. Sólo la apertura. Medirla exige credenciales propias dentro del aislado de segundo plano |
| **Preferencias por categoría** | Que la persona elija recibir unos avisos y otros no. Espera al servicio |
| **La bandeja** | Ver dentro de la app lo que llegó. Espera al servicio |
| **iOS** | Necesita Mac, teléfono físico y la clave de APNs del comercio |
| **Idempotencia** | El paquete de envío manda la clave; el servicio todavía no la hace cumplir |

## Si querés ubicación

El paquete la pide, la lee y la manda. Lo único que agrega el comercio es **un renglón** en
`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

🔴 **Ese renglón no puede venir del paquete**, y conviene entender por qué: Android exige que
sea la aplicación la que declare qué precisión quiere, y esa es una decisión de producto.
`COARSE` es la zona y la acepta cerca del 40% de la gente; `FINE` es la posición exacta, la
acepta el 25% y además obliga a declararla aparte en Play Console. El paquete no puede elegir
eso por el comercio.

Sin el renglón, `pedirUbicacion()` no muestra ningún diálogo: el sistema niega el permiso sin
preguntar y no hay error que lo explique.

Después, todo lo demás es del paquete:

```dart
if (await AkPush.sePuedePedirUbicacion) {
  // Tu pantalla explicando para qué sirve, con tu voz.
  if (loAcepta) await AkPush.pedirUbicacion();
}

await AkPush.reportarUbicacion();   // lee y manda, con freno de 6 horas
```

Se piden **la zona, no la puerta**, se guardan las últimas 5 posiciones y se descartan a los
90 días.

---

## Ubicación continua: los tres modos

Desde el 2026-09-05 el comercio elige, desde su consola, **cómo** se lee la ubicación. No es
«más o menos seguido» de lo mismo: son tres mecanismos distintos, con tres permisos distintos
y tres costos distintos.

| Modo | Qué hace | Qué permiso exige | Qué pasa si falta |
|---|---|---|---|
| `alEntrar` **(por omisión)** | Una lectura cuando la persona abre la app, con freno de 2 h | `ACCESS_COARSE_LOCATION` | No lee nada; `AkPush.reportarUbicacion()` devuelve `false` y el diagnóstico dice por qué |
| `enPrimerPlano` | Lecturas cada 2 min **mientras la app está abierta**. Se corta sola al irse al fondo | **Ninguno nuevo.** El mismo `ACCESS_COARSE_LOCATION` | Igual que arriba |
| `enSegundoPlano` | Lecturas cada 30 min **con la app en el fondo**. Aviso fijo en la barra | `ACCESS_BACKGROUND_LOCATION` **+** `FOREGROUND_SERVICE` **+** `FOREGROUND_SERVICE_LOCATION` (Android 14+) | 🔴 **El modo se apaga solo**, escribe por qué en el diagnóstico y sigue leyendo como `alEntrar`. Nunca mide en silencio |

Nadie cambia de comportamiento por actualizar el paquete: si el comercio no configura nada,
el modo es `alEntrar` y todo funciona como antes.

### 🔴 El SDK NO declara el permiso de segundo plano, y no lo va a declarar

Un permiso escrito en el manifiesto de un paquete se le inyecta a **toda** aplicación que lo
instale, la use o no. Si `hz_collection_sdk` declarara `ACCESS_BACKGROUND_LOCATION`, se lo
impondría también a los comercios de crédito — y **la política de préstamos personales de
Google Play lo prohíbe**. Es de las que sacan la app de la tienda, no de las que piden un
formulario. Es exactamente el error que se le midió a CredoLab, cuyos paquetes le meten
`READ_CONTACTS` y `READ_CALENDAR` a cualquiera.

Entonces: **lo declara la aplicación que embebe el SDK**, y el SDK lo usa **sólo si está
declarado y sólo si el comercio activó el modo**. Una app de préstamos simplemente no lo
declara y el código se comporta como siempre. `bin/muro.dart` lo comprueba en cada
compilación:

```bash
dart run hz_collection_sdk:muro --rubro=prestamoPersonal
```

### Si tu aplicación SÍ lo necesita: lo que agregás vos

Antes de copiar esto, leé la línea siguiente entera. **Estás aceptando** llenar el Formulario
de Declaración de Permisos en Play Console, grabar un video de 30 segundos mostrando la
función, y una revisión manual de Google que se rechaza seguido y que no tiene apelación
documentada. Los cuatro requisitos, con su fuente, están en la ficha de
`ACCESS_BACKGROUND_LOCATION` en `lib/src/permisologia/catalogo_de_permisos.dart`.

En `android/app/src/main/AndroidManifest.xml`:

```xml
<!-- La zona. Este ya lo tenías. -->
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>

<!-- 🔴 Los tres de abajo son SÓLO para el modo `enSegundoPlano`.
     Si tu rubro es préstamo personal o adelanto de sueldo, NO los pongas:
     Google Play los veta y te saca la aplicación de la tienda. -->
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
```

En iPhone, en `ios/Runner/Info.plist`:

```xml
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Para saber en qué zona estás incluso cuando la aplicación está cerrada.</string>
<key>UIBackgroundModes</key>
<array><string>location</string></array>
```

Sin cualquiera de esos renglones, CoreLocation **no entrega nada en el fondo y no tira ningún
error**. El SDK los comprueba y te lo dice.

### Cómo saber si quedó andando

```dart
// ¿La aplicación declaró lo que hace falta?
if (!await AkPush.sePuedeUbicacionEnSegundoPlano) {
  print('Falta declarar: ${AkPush.faltaDeclararParaElFondo}');
}

AkPush.modoDeUbicacionPedido;          // lo que pidió el comercio
AkPush.modoDeUbicacion;                // lo que de verdad está corriendo
AkPush.porQueNoHayLecturaContinua;     // null si están corriendo el mismo
AkPush.lecturasDeUbicacionDeLaSesion;  // (leidas: 8, enviadas: 3)

await AkPush.detenerLecturaContinua(); // cortarlo desde tu propia pantalla
```

`AkPush.diagnostico()` muestra lo mismo en una línea, y marca el eslabón de ubicación en
**ROTO** cuando el modo pedido no arrancó.

### 🔴 Dos cosas que este modo NO hace, y hay que saberlas antes de venderlo

**1 · No sobrevive a que barran la aplicación.** Mientras la actividad viva —la persona apretó
inicio, apagó la pantalla, está en otra app— las lecturas siguen llegando. Si la barre de las
recientes, o si el fabricante la mata por batería (Honor, Xiaomi y Huawei lo hacen agresivamente),
se cortan hasta que la vuelva a abrir. Sostener eso necesitaría un servicio con su propio
isolate, y ese paquete le inyectaría permisos a **toda** aplicación que instale el SDK: es el
mismo muro de arriba.

**2 · Los quince días no entran en el servicio, todavía.** El back guarda las últimas **60**
posiciones por aparato. A 30 minutos son 48 por día, así que esas 60 cubren **25 horas**: un
día entero, que es la pregunta «cuánto se mueve en el día». Para quince días harían falta 720
huecos, o que el servicio agregue por día. **Eso se arregla del lado del servicio, no del SDK**
— bajar la frecuencia para que entren quince días la dejaría en una lectura cada seis horas,
que es el freno que se acaba de sacar por inútil.

### Cuánto cambia, medido

Medido el 2026-09-05 contra el código real, con el reloj comprimido (un teléfono Honor no
estaba conectado, así que esto **no** es una medición en hardware). El día simulado son 11
horas con tres sesiones de 3 minutos —alguien que abre la aplicación tres veces en una
mañana y después la deja en el bolsillo—:

| Modo | Posiciones enviadas en ese día |
|---|---|
| `alEntrar` (lo de hoy) | **1** |
| `enPrimerPlano`, 2 min | **6** |
| `enSegundoPlano`, 30 min | **22** |

El 1 no es un error de la medición: el freno de 2 horas es exactamente eso. La segunda y la
tercera sesión de la mañana caen dentro de la ventana de la primera y no dejan marca. Una sola
posición no distingue a quien se quedó en su casa de quien cruzó la ciudad — que es toda la
razón por la que existen los otros dos modos.

### La frecuencia

Configurable por comercio, en la política de ubicación:

| Campo | Por omisión | Piso |
|---|---|---|
| `cadaMinutosEnPrimerPlano` | 2 min | 1 min |
| `cadaMinutosEnSegundoPlano` | **30 min** | 5 min |

**Por qué 30 minutos.** Tres razones y las tres tiran igual: *(a)* Android limita por su cuenta
a una lectura por hora a las apps en el fondo sin servicio en primer plano, así que 30 min es
el doble de lo que el sistema considera razonable y lo máximo defendible como «conservador»;
*(b)* con 60 huecos en el servicio, 30 min cubren exactamente un día; *(c)* hay un aviso fijo
en la barra de la persona todo el día, y cuanto menos se le caliente el teléfono, más dura el
permiso. Se lee con `LocationAccuracy.low` —antenas y wifi, **sin GPS**— y con el *wake lock*
apagado, así que el teléfono duerme entre lecturas.
