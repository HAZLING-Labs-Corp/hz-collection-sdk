# Un perfil de lanzamiento por comercio

## 🔴 Empezá por `demostracion.sh` — 2026-09-06

**Ya no hace falta un perfil por comercio.** `demostracion.sh` compila la aplicación con
el **llavero**: al arrancar pregunta a qué comercio entrar, y desde el botón de la cabecera
se cambia a otro **sin recompilar**. La lista sale de Collection.

```bash
./example/comercios/demostracion.sh              # emulador de Android
./example/comercios/demostracion.sh 192.168.1.40 # teléfono real: la IP de la máquina
```

Los perfiles por comercio (`rodar.sh`, `mundototal.sh`) siguen sirviendo para compilar
contra UNO solo —una prueba aislada, un APK para repartir— y para eso está el resto de
este documento.

---

Esta aplicación es **una sola** y se compila para varios comercios. No hay una copia por
comercio y no hay ningún archivo que editar antes de correrla: el comercio **sale de la
llave**, y lo único que cambia entre uno y otro son los cuatro valores que se pasan al
compilar.

Cada archivo de esta carpeta es ese juego de cuatro valores, escrito y versionado:

```bash
./example/comercios/rodar.sh              # emulador de Android
./example/comercios/rodar.sh 192.168.1.40 # teléfono real: la IP de la máquina
```

## Por qué están versionados y no en un `.env` ignorado

| | |
|---|---|
| **La llave de la aplicación no es un secreto** | va adentro del APK y cualquiera que lo descomprima la lee. Por eso tiene alcance `devices:write` y **no puede enviar ni leer el padrón** |
| **Lo que sí se pierde es el juego completo** | la combinación de llave + paquete + núcleo es lo que hace que la app hable con el comercio correcto. Reconstruirla de memoria es el error que se descubre en la demo |

Lo que **nunca** va acá es `AKPUSH_SECRETO_DE_PRUEBA`: ése es el secreto con el que se
firma el `userId` y vive en el backend del comercio. En el repositorio dejaría de probar
nada.

## Los cuatro valores, y qué rompe cada uno si está mal

| Valor | Si está mal |
|---|---|
| `AKPUSH_KEY` | la app habla con **otro comercio** —o con ninguno— y el registro falla con 401 |
| `AKPUSH_URL` | el registro no llega. Si apunta a un back sin la ruta, se traga el error y la app queda «midiendo bien y sin enviar» |
| `NUCLEO_URL` | no hay de dónde sacar las personas: la pantalla de entrada queda sin elenco y lo dice |
| `-Ppaquete` | el servicio devuelve **409** explicando el desacuerdo: ese paquete no está registrado en ese comercio |
