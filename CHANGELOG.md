## 0.3.0 — ubicación continua: tres modos, y el que importa se apaga solo si no puede

**Todo es aditivo. Nada de lo que andaba dejó de andar:** las 251 pruebas pasan (eran 228), el
muro de permisos sigue limpio y el manifiesto del paquete **sigue sin declarar un solo
permiso**. Un comercio que no configure nada se comporta exactamente como antes.

### Tres modos de lectura, elegidos por el comercio

| Modo | Qué hace | Permiso |
|---|---|---|
| `alEntrar` **(omisión)** | Una lectura al abrir, con freno de 2 h | `ACCESS_COARSE_LOCATION` |
| `enPrimerPlano` | Cada 2 min mientras la app está abierta; se corta sola al irse al fondo | **ninguno nuevo** |
| `enSegundoPlano` | Cada 30 min con la app en el fondo, con aviso fijo | `ACCESS_BACKGROUND_LOCATION` + `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION` |

Medido con el reloj comprimido contra el código real, un día de 11 h con tres sesiones de 3
minutos: **1 posición** con `alEntrar`, **6** con `enPrimerPlano`, **22** con `enSegundoPlano`.
El 1 no es un error: el freno de 2 h se come la segunda y la tercera sesión de la mañana.

### 🔴 El SDK no declara el permiso de segundo plano, y el modo se apaga solo si falta

Declararlo en el manifiesto del paquete se lo inyectaría a **toda** aplicación que lo instale
—incluidos los comercios de crédito, donde la política de préstamos personales de Google Play
lo prohíbe y saca la app de la tienda—. Lo declara la aplicación anfitriona.

Para que eso no se convierta en un fallo mudo, el plugin nativo gana un método
(`puedeSegundoPlano`) que lee el manifiesto fusionado en Android y el `Info.plist` en iOS y
dice **qué renglón falta**. Si falta alguno, `arrancarContinuo` no abre ningún flujo, escribe
el motivo, y el diagnóstico marca el eslabón de ubicación en **ROTO** con la lista de lo que
hay que declarar. Sin plugin que conteste, la respuesta es «no se puede»: nunca se prende un
servicio en segundo plano a ciegas.

### El consentimiento de «siempre» es una segunda pregunta, con su propia hoja

Android prohíbe pedir los dos permisos juntos: desde Android 11 el diálogo de «permitir
siempre» ni se muestra, el sistema abre los Ajustes. `ModalDeUbicacion.mostrarSiempre` es otra
hoja, con otro ícono, sus propios textos del comercio y un renglón que dice a dónde lleva el
botón. Se anota como consentimiento aparte (`ubicacion_siempre`) y tiene su propio reloj de
reinsistencia.

### Un hallazgo del camino: el muro contaba los permisos comentados

`bin/muro.dart` corría su expresión regular sobre el archivo entero, así que **un permiso
nombrado dentro de un comentario XML contaba como declarado**. Se descubrió al documentar en el
manifiesto del paquete los tres permisos que NO van ahí: el muro dio rojo sobre un archivo que
no declara ninguno. Afecta también el caso normal de un integrador que deja un
`<!-- <uses-permission …> -->` mientras decide. Ahora se sacan los comentarios primero.

### 🔴 Dos límites que no se resolvieron acá, y hay que saberlos

**El segundo plano no sobrevive a que barran la aplicación.** Mientras la actividad viva
—inicio apretado, pantalla apagada, otra app adelante— las lecturas siguen. Si la persona la
barre de las recientes, se cortan. Sostener eso necesita un servicio con su propio isolate, y
ese paquete inyectaría permisos a toda aplicación que instale el SDK.

**Los quince días no entran en el servicio.** El back guarda 60 posiciones por aparato. A 30
min son 48 al día: esas 60 cubren 25 horas. Para quince días harían falta 720 huecos, o que el
servicio agregue por día. Se arregla del lado del servicio.

### Superficie nueva

`ModoDeLectura`, `TextosDeSiempre`, `PoliticaDeUbicacion.modo`, `.cada`,
`.cadaMinutosEnPrimerPlano`, `.cadaMinutosEnSegundoPlano`, `.textosDeSiempre`;
`AkPush.modoDeUbicacion`, `.modoDeUbicacionPedido`, `.porQueNoHayLecturaContinua`,
`.sePuedeUbicacionEnSegundoPlano`, `.faltaDeclararParaElFondo`, `.tieneUbicacionSiempre`,
`.lecturasDeUbicacionDeLaSesion`, `.detenerLecturaContinua()`, `.ofrecerUbicacionSiempre()`;
`EstadoDeUbicacion.modoPedido`, `.modoActivo`, `.faltaDeclarar`, `.lecturasDeLaSesion`,
`.enviosDeLaSesion`, `.elModoNoArranco`; `ModalDeUbicacion.mostrarSiempre`. Dos fichas nuevas
en el catálogo: `FOREGROUND_SERVICE` y `FOREGROUND_SERVICE_LOCATION`.

---

## 0.2.0 — SOL-002 · comportamiento propio y política de transmisión

**Todo es aditivo. Nada de lo que andaba dejó de andar:** las 223 pruebas del paquete pasan, el
muro de permisos sigue limpio —el módulo nuevo **no declara ni un permiso**— y el catálogo se
sigue generando igual.

### Se mide el comportamiento dentro de la propia aplicación

Sesión (cuándo abre, cuándo cierra, cuánto duró, a qué hora local), formulario (cuándo lo abre,
cuánto tarda en enviarlo, cuántas veces lo abandona y vuelve) y campos (si pega el dato o lo
escribe, y cuántas veces lo corrige). Siete tipos de evento, los del contrato del 2026-09-04.

🔴 **El contenido de lo que la persona escribe NO se captura, y es un límite duro.** Ni el texto,
ni su largo, ni un hash de él. Hay una prueba que lo comprueba con una cédula de verdad.

### La política de transmisión

|  | antes | ahora |
|---|---|---|
| cuándo se mide | al abrir | al abrir |
| cuándo se transmite | **en el mismo acto de medir** | por lote, al abrir |
| qué dispara un envío | **nada: siempre** | sólo un cambio real (10 señales de momento no cuentan) |
| sin conexión | **se perdía** | hasta 1.000 eventos ó 512 KB, se descarta lo más viejo |
| resincronización | **no había** | todo igual cada 7 días |

Medido en el emulador contra un simulador que cuenta peticiones, misma sesión repetida:
**5 llamadas y 3.906 bytes → 4 llamadas y 1.050 bytes.** Las mediciones de señales pasaron de 2
por sesión a 0 mientras el teléfono no cambia, y vuelven en cuanto cambia algo de verdad.

Se vuelve al comportamiento anterior en una línea:
`AkPush.init(…, politicaDeTransmision: PoliticaDeTransmision.comoEstabaAntes)`.

### Un hallazgo del camino

`hd_ram_libre_mb` y `hd_ram_en_las_ultimas` **no están en `SENALES_DE_MOMENTO` del servicio y
tendrían que estar.** Con el delta andando, una sesión sin tocar nada seguía transmitiendo las
105 señales por culpa de uno solo de esos dos campos. Quedan en
`momentosQueElBackTodaviaNoTiene`, aparte de los diez del servicio, hasta que se agreguen allá.

### Superficie nueva

`AkPush.formulario(…)` · `AkPush.estadoDelComportamiento()` ·
`AkPush.transmitirComportamiento()` · `AkPush.politicaDeTransmision` ·
`AkPush.ultimasDecisiones`

## 0.0.1

* TODO: Describe initial release.
