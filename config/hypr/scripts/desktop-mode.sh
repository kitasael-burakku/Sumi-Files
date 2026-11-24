#!/usr/bin/env bash
# Suelo de recuperación sin shell: valores habituales, sin snapshot ni perfiles.
# El motor con snapshot es services/Modes; este script nunca para la shell.
set -u
cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
state="$cache_home/sumi-desktop-mode"
runtime="${XDG_RUNTIME_DIR:?}"
case "${1:-}" in
    status) cat "$state" 2>/dev/null || echo normal; exit 0 ;;
    normal) ;;
    *) echo "The shell must be running for focus, gaming or cinema. Usage: desktop-mode.sh normal|status" >&2; exit 2 ;;
esac
failed=0
run() { "$@" || failed=1; }
run hyprctl eval 'hl.config({ decoration = { blur = { enabled = true } }, animations = { enabled = true }, plugin = { dynamic_cursors = { enabled = true } } })'
run bash "$HOME/.config/hypr/scripts/wallpaper-video-pause.sh" off
run powerprofilesctl set balanced
# Sólo el proceso antiguo identificado por su pidfile y su cmdline puede morir.
pidfile="$runtime/sumi-hypridle-raw.pid"
if [ -f "$pidfile" ]; then
    read -r rawpid < "$pidfile" || true
    if [[ "${rawpid:-}" =~ ^[0-9]+$ ]] && [ -r "/proc/$rawpid/cmdline" ]; then
        if tr '\0' ' ' < "/proc/$rawpid/cmdline" | rg -q '^hypridle -c .*/hypridle-focus\.conf'; then
            kill "$rawpid" || failed=1
        fi
    fi
    rm -f "$pidfile"
fi
run systemctl --user start hypridle.service
# El suelo invalida el snapshot anterior antes de arrancar la shell.
rm -f "$runtime/sumi-modes.json"
mkdir -p "$cache_home"
printf normal > "$state"
run systemctl --user start sumi-shell.service
out=$(qs -c sumi ipc call sumi notifDnd false 2>/dev/null) || failed=1
[ "$failed" = 0 ] || echo 'Recovery completed with errors; check the session state.' >&2
exit "$failed"
