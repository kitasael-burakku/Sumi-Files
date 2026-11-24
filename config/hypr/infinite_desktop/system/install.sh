#!/bin/bash
# Instala el lector de entrada de Infinite Desktop como servicio del sistema.
#   pkexec bash ~/.config/hypr/infinite_desktop/system/install.sh
# Vuelve a ejecutarlo tras modificar input_reader.py: la copia que corre es la
# de /usr/local/lib (de root), no la de ~/.config.
# Deshacer: pkexec bash ~/.config/hypr/infinite_desktop/system/uninstall.sh
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: ejecútalo con pkexec (o sudo)."; exit 1; }

# Usuario de la sesión que podrá conectarse al socket.
if [ -n "${PKEXEC_UID:-}" ]; then
    TARGET_USER=$(getent passwd "$PKEXEC_UID" | cut -d: -f1)
else
    TARGET_USER=${SUDO_USER:-}
fi
[[ "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] && [ "$TARGET_USER" != root ] \
    || { echo "ERROR: no pude determinar tu usuario (PKEXEC_UID/SUDO_USER)."; exit 1; }

SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
LIB=/usr/local/lib/infinite-desktop
UNITS=/etc/systemd/system

for f in input_reader.py infinite-input.socket infinite-input.service; do
    [ -f "$SRC/$f" ] || { echo "ERROR: falta $SRC/$f"; exit 1; }
done
getent group input >/dev/null || { echo "ERROR: no existe el grupo 'input'."; exit 1; }
/usr/bin/python3 -I -c 'import evdev' 2>/dev/null || { echo "ERROR: falta python-evdev (pacman -S python-evdev)."; exit 1; }
/usr/bin/python3 -I -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$SRC/input_reader.py" \
    || { echo "ERROR: input_reader.py tiene errores de sintaxis."; exit 1; }

echo "==> Usuario autorizado en el socket: $TARGET_USER"
install -d -m 0755 -o root -g root "$LIB"
install -m 0644 -o root -g root "$SRC/input_reader.py" "$LIB/input_reader.py"
sed "s/@USER@/$TARGET_USER/g" "$SRC/infinite-input.socket" > "$UNITS/infinite-input.socket"
install -m 0644 -o root -g root "$SRC/infinite-input.service" "$UNITS/infinite-input.service"
chmod 0644 "$UNITS/infinite-input.socket"

systemd-analyze verify "$UNITS/infinite-input.socket" "$UNITS/infinite-input.service"
systemctl daemon-reload
systemctl enable --now infinite-input.socket
# Si ya estaba corriendo una versión anterior, reiniciarla para cargar la nueva.
systemctl try-restart infinite-input.service

echo "==> Instalado:"
ls -ld "$LIB"; ls -l "$LIB/input_reader.py" "$UNITS"/infinite-input.*
ls -l /run/infinite-input.sock
