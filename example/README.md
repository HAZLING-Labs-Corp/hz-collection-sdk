# Ejemplo de `hz_collection_sdk`

Una aplicación en blanco que sólo instala el SDK. Sirve para ver el flujo
completo y para probar contra un servicio de verdad.

```bash
flutter run \
  --dart-define=AKPUSH_KEY=pk_live_… \
  --dart-define=AKPUSH_URL=http://10.0.2.2:3085/api/v1 \
  --dart-define=NUCLEO_URL=http://10.0.2.2:3010
```

`NUCLEO_URL` es **de dónde salen las personas**: `hz-mundototal-core`, el sistema
de origen del comercio. Desde un teléfono de verdad, en vez de `10.0.2.2` va la
IP de la máquina en la red.

Dos variables, y ninguna es secreta: la llave de la aplicación va adentro del
APK y cualquiera que lo descomprima la lee — por eso tiene alcance
`devices:write` y **no puede enviar**. El comercio no se configura: sale de la
llave.

`10.0.2.2` es cómo un emulador de Android alcanza el localhost de la máquina que
lo hospeda. Desde un teléfono real en la misma red, la IP de la máquina.

---

## El identificador del paquete

El servicio verifica que el paquete que pide la configuración esté registrado en
tu comercio: con otro devuelve un 409 explicando el desacuerdo. Así que el
ejemplo tiene que compilarse con **el tuyo**, y se pasa al compilar:

```bash
flutter run -Ppaquete=com.tuempresa.app --dart-define=AKPUSH_KEY=…
```

**No hay ningún archivo que editar.** Lo único que falta es registrar ese paquete
en tu comercio, desde la consola.

Sin `-Ppaquete` usa `com.juanpush.android1`, que es una app de prueba nuestra y
no va a servirte.

---

## Qué se ve

La aplicación arranca **sin pedir ningún permiso** —lo decide la política— y
muestra en qué estado está: si esa persona puede recibir avisos y por qué no, si
la hay.

Entrás eligiendo una de **cien personas de prueba** (`usuario1`…`usuario100`,
buscables por nombre, cédula o usuario). Ahí se dispara el ciclo de sesión: se da
de baja a la anterior si era otra, se verifica el permiso contra el sistema
operativo, y se registra.

Si la política dice pregunta blanda, aparece **el modal con los textos del
comercio**. Un «ahora no» no gasta el diálogo del sistema; un «sí» lo dispara.

El botón del ícono de la cabecera abre el **diagnóstico**: por qué no le llega, si
no le llega.

---

## Las personas ya no viven acá — 2026-09-05

Hasta el 2026-09-05 esta aplicación llevaba **104 personas compiladas adentro**,
en `lib/personas_de_prueba.dart`. Ese archivo **ya no existe**.

El problema no era de orden: para corregir una cédula, agregar una empresa o
arreglar un correo había que **recompilar el APK y volver a repartirlo**. El
juego de prueba era intocable, que es lo contrario de un juego de prueba.

Ahora las personas viven en **`hz-mundototal-core`**, el *sistema de origen* del
comercio — el que las posee. Esta aplicación es un **consumidor**, igual que
notificaciones. Y **no guarda copia**: si el núcleo no contesta, la pantalla lo
dice nombrando la ruta que falta, en vez de fingir que tiene gente.

Dos llamadas, en `lib/nucleo.dart`:

| | Para qué |
|---|---|
| `POST /api/auth/login` | usuario y clave → la persona y una sesión firmada |
| `GET /api/contactos` | el directorio, buscable · **pide sesión** |

### Ahora se entra de verdad

Antes se **elegía de una lista** y se entraba sin clave: `claveDePrueba` estaba
declarada y no la usaba nadie. Elegir de una lista no es entrar, y la app de
prueba tiene que probar el camino real.

Hoy se escribe **usuario y clave**. La semilla del núcleo trae `usuario1` …
`usuario100` con clave `admin123`.

> 🔴 **Cien cuentas con la misma clave conocida no salen de un ambiente de
> prueba.** Es cómodo para entrar con cualquiera sin ir a buscar nada, y es
> exactamente lo que no se hace donde haya datos de alguien. Toda persona creada
> a mano en el núcleo lleva su propia clave.

### El directorio se ve después de entrar

El núcleo lo protege con sesión: el elenco son personas con cédula, ciudad y
correo, y un directorio abierto es una cartera publicada. Tocar a alguien en la
lista **completa el usuario**; entrar sigue necesitando la clave.

### Los cuatro casos de identidad

Las dos empresas con RIF y los dos empleados de un proveedor **ya están en el
directorio**, junto a las cien. Habían sido sacados del selector el 2026-09-04
porque no existían en notificaciones —un push a ellos salía bien y no le llegaba
a nadie, el falso positivo más caro de depurar—. Eso se resuelve del lado del
núcleo: se mandan a notificaciones con el resto del elenco.

### La semilla está anonimizada

Los cien del Excel son personas reales. En el núcleo se conserva la forma
—cédula venezolana, +58, estados y ciudades reales— y se reemplazan nombre,
teléfono y correo por sintéticos: teléfonos del bloque `555`, que no está
asignado a nadie, y correos `@ejemplo.mundototal.test`, un TLD que no puede
existir. La demo manda SMS y push de verdad.
