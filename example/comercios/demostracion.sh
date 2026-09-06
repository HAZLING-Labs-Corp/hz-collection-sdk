#!/usr/bin/env bash
#
# DEMOSTRACIÓN — la aplicación con el LLAVERO, para moverse entre todos los comercios
#
# Es el perfil que hay que usar de acá en adelante. Los otros dos —`rodar.sh` y
# `mundototal.sh`— compilan contra UN comercio y siguen sirviendo para eso; éste no
# compila contra ninguno: **pregunta al arrancar y se cambia sin recompilar**.
#
#   ./example/comercios/demostracion.sh                 desde un emulador de Android
#   ./example/comercios/demostracion.sh 192.168.1.40    desde un teléfono real
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

ANFITRION="${1:-10.0.2.2}"

# La llave del llavero. No es un secreto en el sentido fuerte —viaja dentro del APK, como
# cualquier llave de aplicación— y por eso el llavero sólo entrega llaves que registran
# aparatos, y sólo de comercios marcados de demostración.
LLAVERO_LLAVE="${LLAVERO_LLAVE:-llavero-de-demostracion-en-calidad}"

# 🔴 El paquete tiene que estar registrado en TODOS los comercios de la lista, no sólo en
# el primero: al cambiarse a uno donde no esté, el servicio contesta 404 y el selector lo
# muestra como «le falta». Los comercios clonados de Mundo Total comparten sus cinco
# paquetes, así que con éste alcanza para todos ellos.
PAQUETE="${PAQUETE:-com.hazling.creditotal}"

echo "▶ Demostración · llavero http://$ANFITRION:3085/api/llavero · paquete $PAQUETE"
echo "  El comercio NO se elige acá: lo pregunta la app al arrancar."

exec flutter run \
  -Ppaquete="$PAQUETE" \
  -Pnombre="Collection" \
  --dart-define=APP_NOMBRE=Collection \
  --dart-define=LLAVERO_URL="http://$ANFITRION:3085/api/llavero" \
  --dart-define=LLAVERO_LLAVE="$LLAVERO_LLAVE" \
  --dart-define=AKPUSH_URL="http://$ANFITRION:3085/api/v1"
