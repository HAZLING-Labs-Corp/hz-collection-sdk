#!/usr/bin/env bash
#
# DEMOSTRACIÓN — la aplicación con el LLAVERO, para moverse entre todos los comercios
#
# Es el perfil que hay que usar de acá en adelante. Los otros dos —`rodar.sh` y
# `mundototal.sh`— compilan contra UN comercio y siguen sirviendo para eso; éste no
# compila contra ninguno: **pregunta al arrancar y se cambia sin recompilar**.
#
#   ./example/comercios/demostracion.sh https://back-production-733d.up.railway.app
#                                                       contra Collection en Railway ← ASÍ
#   ./example/comercios/demostracion.sh 192.168.1.40    contra un Collection local, desde un
#                                                       teléfono real en la misma red
#   ./example/comercios/demostracion.sh                 contra un Collection local, emulador
#
# 🔴 CONTRA RAILWAY, NO CONTRA LOCAL. Pedido de Juan, 2026-09-07: *«todo va hacia Railway en
# la app, nada contra local»*. Y tiene una razón que se paga caro: con Collection local, la
# app anda en esta máquina y en ningún teléfono de nadie más —el `10.0.2.2` sólo existe
# dentro del emulador—, así que una demostración desde otro aparato falla sin motivo
# aparente. Y peor: media demostración contra Railway y media contra local deja los aparatos
# registrados en DOS bases distintas, y la consola de una no muestra lo que hizo la otra.
#
# Del lado de Collection hacen falta dos variables en su `.env`, y sin las dos la ruta
# del llavero NO EXISTE:
#
#   LLAVERO_DE_DEMOSTRACION=on
#   LLAVE_DEL_LLAVERO=<la misma que se pasa acá abajo>
#
# Y cada comercio que se quiera ver en la lista se marca una vez:
#
#   npm run demostracion -- marcar --slug <slug> --nucleo <url del núcleo>
#   npm run demostracion -- llave  --slug <slug> --llave <su llave de devices:write>
#
set -euo pipefail

# El primer argumento es O una dirección completa —`https://…`, la de Railway— O un host
# suelto, que se completa con el puerto local. Se distingue por el `http`, y no con una
# bandera aparte: quien pega una URL de Railway espera que funcione pegada.
#
# El puerto sólo aplica al caso local. Se puede cambiar porque pasa de verdad: con dos ramas
# del back levantadas a la vez —una por desarrollador— la segunda corre en otro puerto, y
# una dirección fija manda la app a la instancia equivocada sin que nada falle.
PUERTO="${PUERTO:-3085}"
DESTINO="${1:-10.0.2.2}"

if [[ "$DESTINO" == http://* || "$DESTINO" == https://* ]]; then
  # Sin la barra final: abajo se concatena `/api/…` y `//api` da 404 en algunos ruteadores.
  BASE="${DESTINO%/}"
else
  BASE="http://$DESTINO:$PUERTO"
fi

# La llave del llavero. No es un secreto en el sentido fuerte —viaja dentro del APK, como
# cualquier llave de aplicación— y por eso el llavero sólo entrega llaves que registran
# aparatos, y sólo de comercios marcados de demostración.
LLAVERO_LLAVE="${LLAVERO_LLAVE:-llavero-de-demostracion-en-calidad}"

# 🔴 El paquete tiene que estar registrado en TODOS los comercios de la lista, no sólo en
# el primero: al cambiarse a uno donde no esté, el servicio contesta 404 y el selector lo
# muestra como «le falta». Los comercios clonados de Mundo Total comparten sus cinco
# paquetes, así que con éste alcanza para todos ellos.
PAQUETE="${PAQUETE:-com.hazling.creditotal}"

echo "▶ Demostración · llavero $BASE/api/llavero · paquete $PAQUETE"
echo "  El comercio NO se elige acá: lo pregunta la app al arrancar."
# El aviso, porque es el error que cuesta una demostración: si esto dice `10.0.2.2` o
# `localhost`, la app sólo funciona en el emulador de esta máquina.
[[ "$BASE" == *"10.0.2.2"* || "$BASE" == *"localhost"* || "$BASE" == *"127.0.0.1"* ]] \
  && echo "  ⚠️  Collection LOCAL: esto no funciona desde otro teléfono. Pasale la dirección de Railway."

exec flutter run \
  -Ppaquete="$PAQUETE" \
  -Pnombre="Collection" \
  --dart-define=APP_NOMBRE=Collection \
  --dart-define=LLAVERO_URL="$BASE/api/llavero" \
  --dart-define=LLAVERO_LLAVE="$LLAVERO_LLAVE" \
  --dart-define=AKPUSH_URL="$BASE/api/v1"
