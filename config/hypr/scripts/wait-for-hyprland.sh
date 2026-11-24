#!/usr/bin/env bash
# ============================================================================
#  wait-for-hyprland.sh — bounded wait for Hyprland to actually be ready
# ----------------------------------------------------------------------------
#  Replaces the fixed `sleep 0.5` / `sleep 2` calls that used to be in
#  autostart.lua (timing bets on how long the compositor/daemons take to
#  start) with a real poll on `hyprctl monitors`, with a max timeout so it
#  doesn't block startup indefinitely. A timeout FAILS the caller's
#  ExecStartPre: starting a Wayland client without its compositor only creates
#  another crash. Restart policy belongs to each consuming service.
#
#  Usage: wait-for-hyprland.sh [timeout_in_seconds=5]
# ============================================================================

set -u

wait_seconds="${1:-5}"
if [[ ! "$wait_seconds" =~ ^[0-9]+$ ]] || ((${#wait_seconds} > 4)); then
    echo "wait-for-hyprland: expected an integer timeout (0–9999 seconds)" >&2
    exit 2
fi
wait_seconds=$((10#$wait_seconds))
command -v hyprctl >/dev/null 2>&1 || {
    echo "wait-for-hyprland: hyprctl is unavailable" >&2
    exit 127
}

deadline=$((SECONDS + wait_seconds))
while ! timeout --kill-after=1 1 hyprctl monitors >/dev/null 2>&1; do
    if ((SECONDS >= deadline)); then
        echo "wait-for-hyprland: compositor unavailable after ${wait_seconds}s" >&2
        exit 1
    fi
    sleep 0.1
done

exit 0
