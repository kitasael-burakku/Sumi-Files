#!/bin/bash
# Desinstala el lector de entrada de Infinite Desktop.
#   pkexec bash ~/.config/hypr/infinite_desktop/system/uninstall.sh
# Ojo: sin el lector (y sin el grupo 'input'), el canvas no recibe eventos.
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "ERROR: ejecútalo con pkexec (o sudo)."; exit 1; }

systemctl disable --now infinite-input.socket infinite-input.service 2>/dev/null
rm -fv /etc/systemd/system/infinite-input.socket /etc/systemd/system/infinite-input.service
rm -rfv /usr/local/lib/infinite-desktop
systemctl daemon-reload
systemctl reset-failed infinite-input.service infinite-input.socket 2>/dev/null
echo "==> Desinstalado."
