#!/usr/bin/env bash
#
# RODAR — la aplicación de Collection apuntando al comercio `rodar`
#
# El comercio se dio de alta el 2026-09-06 clonando la configuración de `mundototal`:
# mismo proyecto de Firebase (`mundototal-72162`, cuenta de la plataforma) y los mismos
# paquetes ya registrados, así que el push le llega sin registrar nada nuevo en Firebase.
#
#   ./example/comercios/rodar.sh                 desde un emulador de Android
#   ./example/comercios/rodar.sh 192.168.1.40    desde un teléfono real, en la misma red
#
set -euo pipefail

# `10.0.2.2` es cómo un emulador de Android alcanza el localhost de la máquina que lo
# hospeda. Desde un teléfono de verdad no existe: va la IP de la máquina en la red.
ANFITRION="${1:-10.0.2.2}"

# La llave `devices:write` del comercio `rodar`. No es un secreto: va adentro del APK.
# Emitida el 2026-09-06 por `npm run comercio-nuevo -- claves --slug rodar`.
LLAVE="${AKPUSH_KEY:-pk_live_c0a5669a8c802951.lILRmcamJhmsG3aCUcTt5YaxDgevE8lLiAtrwWTcs_Y}"

# EL NÚCLEO DE RODAR — ya existe, desde el 2026-09-07.
#
# `NUCLEO_URL` es de dónde salen las personas: el sistema de origen del comercio, el que
# las POSEE. El de Rodar es su propio back, desplegado en Railway, y contesta
# `GET /api/contactos` con llave de consulta (`contactos:leer`) igual que el de Mundo
# Total. Se cambia por fuera:  NUCLEO_URL=http://... ./example/comercios/rodar.sh
#
# 🔴 PERO ESTE SCRIPT NO ES EL CAMINO RECOMENDADO. Compila contra UN comercio y le pasa
# la llave a mano; `demostracion.sh` no compila contra ninguno y saca la dirección Y la
# llave del llavero, que es donde viven de verdad. Este queda para probar el comercio
# aislado, sin llavero de por medio.
NUCLEO="${NUCLEO_URL:-https://back-production-386b.up.railway.app}"

# Uno de los paquetes que ya están registrados en el comercio (se clonaron los cinco de
# Mundo Total). Con un paquete que no esté registrado, el servicio contesta 409.
PAQUETE="${PAQUETE:-com.hazling.creditotal}"

echo "▶ Rodar · núcleo $NUCLEO · servicio http://$ANFITRION:3085 · paquete $PAQUETE"
# El aviso sigue, apuntando al caso que de verdad engaña: si alguien deja el núcleo de
# Mundo Total puesto, la app muestra 104 personas que no son de Rodar y NADA falla.
[[ "$NUCLEO" == *":3010"* || "$NUCLEO" == *"core-production"* ]] \
  && echo "  ⚠️  ese es el núcleo de MUNDO TOTAL: las personas que veas no son de Rodar"

# Sin llave de consulta el directorio no se puede leer y la app pide usuario y clave —que
# en Rodar no existen—. Se avisa acá y no se descubre en la pantalla.
[[ -z "${NUCLEO_LLAVE:-}" ]] \
  && echo "  ⚠️  sin NUCLEO_LLAVE: no vas a ver el directorio. Usá demostracion.sh, que la saca del llavero"

exec flutter run \
  -Ppaquete="$PAQUETE" \
  -Pnombre=Rodar \
  --dart-define=APP_NOMBRE=Rodar \
  --dart-define=AKPUSH_KEY="$LLAVE" \
  --dart-define=AKPUSH_URL="http://$ANFITRION:3085/api/v1" \
  --dart-define=NUCLEO_URL="$NUCLEO" \
  --dart-define=NUCLEO_LLAVE="${NUCLEO_LLAVE:-}"
