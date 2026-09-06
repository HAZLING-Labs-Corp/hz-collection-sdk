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

# 🔴 EL NÚCLEO DE RODAR TODAVÍA NO ESTÁ DEFINIDO.
#
# `NUCLEO_URL` es de dónde salen las personas: el sistema de origen del comercio, el que
# las POSEE. Rodar va a tener el suyo —su propio back, con su propia base— y hasta que se
# diga cuál es, esto apunta al núcleo de Mundo Total para que la app entre y se pueda
# probar el ciclo completo.
#
# Mientras esto siga así, las personas que se vean en la app son las de Mundo Total. Se
# cambia en esta línea, o por fuera:  NUCLEO_URL=http://... ./example/comercios/rodar.sh
NUCLEO="${NUCLEO_URL:-http://$ANFITRION:3010}"

# Uno de los paquetes que ya están registrados en el comercio (se clonaron los cinco de
# Mundo Total). Con un paquete que no esté registrado, el servicio contesta 409.
PAQUETE="${PAQUETE:-com.hazling.creditotal}"

echo "▶ Rodar · núcleo $NUCLEO · servicio http://$ANFITRION:3085 · paquete $PAQUETE"
[[ "$NUCLEO" == *":3010"* ]] && echo "  ⚠️  núcleo provisional: son las personas de Mundo Total"

exec flutter run \
  -Ppaquete="$PAQUETE" \
  -Pnombre=Rodar \
  --dart-define=APP_NOMBRE=Rodar \
  --dart-define=AKPUSH_KEY="$LLAVE" \
  --dart-define=AKPUSH_URL="http://$ANFITRION:3085/api/v1" \
  --dart-define=NUCLEO_URL="$NUCLEO"
