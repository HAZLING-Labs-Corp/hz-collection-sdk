# Instalar el SDK en una aplicación nueva

> Escrito el 2026-09-07, después de perder una tarde con la app de Rodar.
>
> Juan lo dijo así: *«esto no puede ser un error que cada vez que vayamos a instalar no esté
> en el manual de cómo solucionarlo. Siempre nos pasó.»* Tenía razón: pasó con Multivalores,
> pasó con Mundo Total y pasó con Rodar. **El síntoma es distinto cada vez y la causa es
> siempre la misma.**

---

## 🔴 Lo único que hay que entender

La aplicación lleva **una sola credencial**: `COLLECTION_KEY` (`pk_live_…`). Con eso alcanza,
y eso es el diseño: **el SDK pide la configuración de Firebase a Collection** y llama a
`Firebase.initializeApp()` con lo que le contesten. **No hace falta `google-services.json`**
ni el plugin de Gradle de Google. Medido en `ak_push.dart:1354-1373`.

Pero la llave **no identifica a la aplicación**. Identifica al **comercio**. Lo que
identifica a la aplicación es su **identificador de paquete** (`applicationId` en Android,
`bundleId` en iOS). Collection resuelve la configuración con las dos cosas:

```
llave  pk_live_…            →  comercio
paquete com.hazling.rodar   →  qué app de Firebase de ese comercio
```

> ### Si el paquete no está registrado en el comercio, la llave correcta no sirve para nada.
> Y el SDK **no falla**: da de alta la instalación, arranca la serie de comportamiento, y
> vuelve sin configuración. Todo lo demás sigue andando. Los avisos, no.

---

## Los tres pasos, en este orden

### 1. Crear la app en Firebase

En la consola del proyecto del comercio (`Configuración del proyecto → Tus apps → Agregar
app`), con el **mismo** identificador de paquete con el que se compila.

De ahí salen los tres datos que hacen falta:

| dato | dónde se ve en la consola |
|---|---|
| `app_id` | «ID de la app», `1:859769563262:android:…` |
| `api_key` | la clave de API web/Android del proyecto |
| `sender_id` | «ID del remitente», el número del proyecto |

### 2. Registrar el paquete en el comercio de Collection

```bash
npm run comercio-nuevo -- firebase --slug <comercio> \
  --plataforma ANDROID --paquete com.hazling.rodar \
  --app-id 1:…:android:… --api-key AIza… --sender-id 859769563262
```

**Y se comprueba**, que es el paso que nadie hace:

```bash
npm run comercio-nuevo -- ver --slug <comercio>
```

Cada entrada tiene que decir **completa**. Una entrada a la que le falte `api_key` o
`sender_id` produce `appMismatch` con un mensaje distinto —«la configuración está incompleta
del lado del proveedor»— y se busca en el lugar equivocado. Le pasó a
`com.develop.creditotal` el 2026-09-07.

### 3. Los tres datos del `AndroidManifest.xml`

**Los tres, y ninguno lo pone el SDK.** Están medidos el 2026-09-07 contra la app de Rodar,
uno por uno, y cada uno falla de una forma distinta:

```xml
<manifest …>
    <!-- Android 13+ exige PEDIR el permiso de avisos. -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <!-- COARSE, no FINE: al SDK le alcanza la ciudad. -->
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <application …>
        …
        <!-- 🔴 EL QUE NADIE PONE Y EL QUE MÁS DUELE. -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="default" />
    </application>
</manifest>
```

| falta | qué se ve |
|---|---|
| `POST_NOTIFICATIONS` | en Android 13+ el diálogo del permiso no sale nunca |
| `ACCESS_COARSE_LOCATION` | **`AkPush.diagnostico()` ni corre**: `geolocator` lanza «No location permissions are defined in the manifest», que no nombra al SDK y manda a buscar a otro lado |
| `default_notification_channel_id` | 🔴 **el aviso LLEGA y NO SE VE.** FCM devuelve un id, el logcat dice `FlutterFirebaseMessagingBackgroundService started!`, y en la pantalla no aparece nada. Con la app cerrada el aviso lo dibuja Firebase —no el Dart del SDK— y necesita saber en qué canal ponerlo; sin este dato lo manda a uno que no existe y el sistema lo descarta **en silencio** |

`default` es el canal que crea el SDK (`presenter.dart`), con importancia alta. El otro es
`silencioso`, para lo que se pide mostrar sin ruido.

⚠️ **Y al probar a mano, no inventes el nombre del canal.** Un envío con
`android.notification.channelId: 'akpush_default'` —un nombre que no existe— se descarta
igual, y el logcat lo dice: «Notification Channel requested (…) has not been created by the
app». O se manda sin `channelId` y manda el del manifiesto, o se manda `default`.

---

## 🔴 Cómo se diagnostica en diez segundos, sin adivinar

El SDK trae el diagnóstico hecho. **Llamalo antes de investigar cualquier otra cosa:**

```dart
if (kDebugMode) debugPrint(await AkPush.diagnostico());
```

Con el paquete sin registrar contesta esto, y dice la causa en el primer renglón:

```
AkPush — diagnóstico
Qué pasa: El servidor no reconoce a esta aplicación: el identificador de paquete con el
que está compilada no es el que quedó registrado para esta llave.
Eslabón roto: configuracion

  configuración ROTO  no hay
  firebase      ROTO  sin inicializar
  permiso       ROTO  sinPreguntar
  token         ROTO  no hay
  registro      ROTO  sin identify()
  último error        AkPushError(appMismatch): El paquete "com.hazling.rodar" no está
                      registrado en el comercio "rodar".
```

**Poné esa línea en el arranque de toda app nueva.** Es una llamada y ahorra la tarde.

---

## 🔴 Por qué el síntoma engaña: una fila que falta rompe cinco eslabones

Ésta es la razón de que «siempre nos pase» y de que cada vez parezca otra cosa. Sin
configuración se cae **toda la cadena**, y lo que se ve es el último eslabón, no el primero:

```
falta el paquete en el comercio
  └─ appMismatch, y el SDK NO lanza: sigue recolectando
      └─ Firebase nunca se inicializa (no hay opciones que pasarle)
          └─ no se puede PEDIR EL PERMISO      ← «no pide permiso de notificaciones»
              └─ no hay token                   ← «no llega ningún aviso»
                  └─ identify() lanza `notInitialized`
                      └─ 0 aparatos en Collection
          └─ no llega la política de ubicación  ← «no pregunta por la ubicación»
```

**Los cinco síntomas de abajo son el mismo problema de arriba.** Y son los cinco que se
reportan, porque son los que se ven en la pantalla.

### Y ojo con `notInitialized`: la tabla de errores del README engañaba

Decía que `notInitialized` es «llamaste a `identify()` antes de que `init()` terminara». Eso
es **una** de las causas y no es la frecuente. La otra —la que costó la tarde— es que
`init()` **terminó bien** y volvió sin configuración, así que `_asegurarIniciado()` rechaza
igual. Se corrigió en el README el 2026-09-07.

---

## Lo que sí hay que escribir en la app, y nada más

Son cuatro lugares. Se puede copiar de `brokerage-app-front` (Multivalores) o de
`rodar-app`, que hoy son los dos que están al día.

| | dónde | qué |
|---|---|---|
| 1 | antes de montar la app | `await AkPush.init(llave:, url:, pedirPermisoAlIniciar: false)` |
| 2 | la llave del navegador raíz | `final navegadorRaiz = AkPush.navegador` — es la MISMA `GlobalKey`, si no el toque del aviso no navega |
| 3 | al iniciar sesión | `AkPush.alIniciarSesion(userId:, tipo:, documento:, datos:)`, **dentro de un `try`**: nunca tumba el ingreso |
| 4 | al cerrar sesión | `AkPush.alCerrarSesion()` — sin esto el teléfono sigue recibiendo los avisos de quien salió |

Y para que la persona pueda prender los avisos, **una de las dos** (o las dos):

- `AkPush.campanita()` en el `AppBar` — hecha, se actualiza sola al volver de los Ajustes.
- Un cartel en la pantalla con `AkPush.estadoDeAvisos()` + `AkPush.resolverAvisos()` — ver
  `AvisoDePermiso` en Multivalores y `PrendeLosAvisos` en Rodar.

🔴 **`pedirPermisoAlIniciar: false`, siempre.** El permiso se pide cuando la persona entra y
después de explicar para qué sirve. En Android el diálogo del sistema se muestra **una vez**:
un «no» dado en el primer segundo de la primera apertura no se recupera nunca.

🔴 **`try` en el 3 y en el 4, y que el `catch` DIGA POR QUÉ.** Un `catch (_) {}` acá es lo
que hace que el problema se descubra tres días después mirando la base: el 2026-09-07 la app
de Rodar entraba bien, el SDK arrancaba bien, y en Collection había cero aparatos sin una
sola línea en la consola.
