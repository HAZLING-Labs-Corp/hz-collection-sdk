#!/usr/bin/env bash
#
# MUNDO TOTAL — la aplicación de Collection apuntando al comercio `mundototal`
#
# Existe para que el perfil de Rodar no parezca un caso especial: son dos juegos de
# valores para la misma aplicación, y tener los dos escritos es lo que permite mostrarlos
# uno al lado del otro sin reconstruir ninguno de memoria.
#
#   ./example/comercios/mundototal.sh                 desde un emulador
#   ./example/comercios/mundototal.sh 192.168.1.40    desde un teléfono real
#
set -euo pipefail

ANFITRION="${1:-10.0.2.2}"

# 🔴 Poné acá la llave `devices:write` de `mundototal`. No está escrita porque las que
# tiene emitidas hoy no se pueden recuperar de la base —se guarda sólo el hash— y una
# llave inventada da un 401 que parece un problema de red.
#
#   npm run comercio-nuevo -- claves --slug mundototal    (emite tres nuevas)
LLAVE="${AKPUSH_KEY:-}"
if [[ -z "$LLAVE" ]]; then
  echo "Falta la llave. Corré:  AKPUSH_KEY=pk_live_… ./example/comercios/mundototal.sh" >&2
  exit 1
fi

NUCLEO="${NUCLEO_URL:-http://$ANFITRION:3010}"
PAQUETE="${PAQUETE:-com.hazling.creditotal}"

echo "▶ Mundo Total · núcleo $NUCLEO · servicio http://$ANFITRION:3085 · paquete $PAQUETE"

exec flutter run \
  -Ppaquete="$PAQUETE" \
  -Pnombre="Mundo Total" \
  --dart-define=APP_NOMBRE="Mundo Total" \
  --dart-define=AKPUSH_KEY="$LLAVE" \
  --dart-define=AKPUSH_URL="http://$ANFITRION:3085/api/v1" \
  --dart-define=NUCLEO_URL="$NUCLEO"
