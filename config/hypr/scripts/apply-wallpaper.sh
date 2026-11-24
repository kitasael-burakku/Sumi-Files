#!/usr/bin/env bash
# ============================================================================
#  apply-wallpaper.sh — applies a wallpaper (video or image) and persists it
# ----------------------------------------------------------------------------
#  Single source of truth for the mpvpaper/awww flags — they used to live
#  duplicated between hypr/modules/autostart.lua and
#  rofi/scripts/wallpaper_grid.sh (retired with rofi in Fase 10.e), synced by
#  hand with cross-referencing comments.
#
#  Besides applying the wallpaper to the desktop:
#    - persiste la ruta en $XDG_STATE_HOME/sumi-shell/current-wallpaper
#      (por defecto ~/.local/state), para restaurarla en el siguiente inicio.
#    - generates hyprlock/wallpapers/current.png from that same wallpaper,
#      so the lock screen inherits what's showing on the desktop (this is
#      independent of the matugen toggle — it's the wallpaper, not the
#      colors).
#
#  Usage:
#    apply-wallpaper.sh <path>           — every output; clears per-output picks
#    apply-wallpaper.sh <path> <output>  — that output only (persisted apart)
#    apply-wallpaper.sh                  — restores what was persisted, or the
#                                           default if there is none / it no
#                                           longer exists
#    apply-wallpaper.sh --sync           — re-applies the persisted state to
#                                           the outputs there are NOW (hotplug);
#                                           writes nothing
#    apply-wallpaper.sh --clear <output> — that output goes back to the
#                                           wallpaper of every screen (drops its
#                                           exception); colours untouched
#                                           (redesign 12G, 2026-09-28)
#
#  PER-OUTPUT WALLPAPERS (2026-09-23). Two state files, on purpose:
#    - .current-wallpaper is still "the wallpaper of every screen", and still
#      the only thing colours (matugen), hyprlock's current.png, apply-scheme,
#      `minimaru theme` and matugen_toggle read. None of them had to change.
#    - .current-wallpaper-outputs holds the exceptions, one `OUTPUT<TAB>path`
#      line per screen that has its own. Applying to every output empties it.
#  A pick for one output does NOT touch colours or the lock background: those
#  follow the wallpaper of every screen. With a single output connected, a
#  pick "for that output" is a pick for every output — there is no difference
#  to keep apart.
#
#  Before this, <output> only half worked: awww got no `-o` (images landed on
#  every screen) and every mpvpaper was killed before starting one (the other
#  screen lost its video). Now the script reconciles: it works out what each
#  output should show and only touches what differs — it kills the mpvpaper
#  of THAT output, and leaves a video that is already playing where it should.
# ============================================================================

set -u
set -o pipefail

# F1c: mismos formatos; el legado sólo se importa en la migración explícita.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sumi-shell"
STATE_FILE="$STATE_DIR/current-wallpaper"
OUTPUTS_FILE="$STATE_DIR/current-wallpaper-outputs"
# Fallback when nothing was ever picked. Empty by default (Sumi-Files ships no
# wallpaper): set SUMI_DEFAULT_WALLPAPER in the environment, or edit this line.
DEFAULT_WALLPAPER="${SUMI_DEFAULT_WALLPAPER:-}"
HYPRLOCK_BG="$HOME/.config/hyprlock/wallpapers/current.png"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
LOG="$RUNTIME/apply-wallpaper.log"
MPV_OPTS="--loop-file=inf --no-audio --hwdec=auto"

die() {
    echo "$(date) ERROR: $*" >> "$LOG"
    echo "apply-wallpaper: $*" >&2
    exit 1
}

# Callers overlap (the shell's hotplug sync, wallpaper.service, the CLI): one
# at a time, or two of them can each start the same output's mpvpaper.
exec 9>"$RUNTIME/apply-wallpaper.lock"
flock -w 15 9 || die "another apply-wallpaper.sh is still running"

ext_of() {
    printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]'
}

is_video() {
    case "$(ext_of "$1")" in mp4|mkv|mov|webm) return 0 ;; esac
    return 1
}

is_image() {
    case "$(ext_of "$1")" in jpg|jpeg|png|webp|gif) return 0 ;; esac
    return 1
}

# ── Outputs and state ──────────────────────────────────────────────────────

outputs() {
    timeout 2 hyprctl monitors 2>/dev/null | awk '/^Monitor /{ print $2 }'
}

override_of() {
    [ -f "$OUTPUTS_FILE" ] || return 0
    awk -F'\t' -v o="$1" '$1 == o { p = $2 } END { if (p != "") print p }' "$OUTPUTS_FILE"
}

set_override() {
    mkdir -p "$STATE_DIR" || die "can't create $STATE_DIR"
    local tmp
    tmp="$(mktemp "$OUTPUTS_FILE.XXXXXX")" || die "can't write $OUTPUTS_FILE"
    [ -f "$OUTPUTS_FILE" ] && awk -F'\t' -v o="$1" '$1 != o' "$OUTPUTS_FILE" > "$tmp"
    printf '%s\t%s\n' "$1" "$2" >> "$tmp"
    mv -f "$tmp" "$OUTPUTS_FILE"
}

global_wallpaper() {
    local g=""
    [ -f "$STATE_FILE" ] && g="$(cat "$STATE_FILE" 2>/dev/null)"
    { [ -n "$g" ] && [ -f "$g" ]; } || g="$DEFAULT_WALLPAPER"
    printf '%s' "$g"
}

# ── mpvpaper: one instance per output, or one on '*' ──────────────────────

# "<pid>\t<output>\t<path>" for every running mpvpaper. Read from
# /proc/<pid>/cmdline, split on NUL, so a path with spaces stays whole. The
# output and the path are the last two arguments however it was started.
mpv_instances() {
    local pid
    for pid in $(pgrep -x mpvpaper 2>/dev/null); do
        local -a argv=()
        mapfile -d '' -t argv < "/proc/$pid/cmdline" 2>/dev/null || continue
        [ "${#argv[@]}" -ge 3 ] || continue
        printf '%s\t%s\t%s\n' "$pid" "${argv[-2]}" "${argv[-1]}"
    done
}

# Pids of the instances on an output ("" = any output) showing a path
# ("" = any path, "!path" = any other path).
mpv_pids() {
    mpv_instances | awk -F'\t' -v o="$1" -v w="$2" '
        o != "" && $2 != o { next }
        w == ""            { print $1; next }
        substr(w, 1, 1) == "!" { if ($3 != substr(w, 2)) print $1; next }
        $3 == w            { print $1 }'
}

# kill only sends the signal, it doesn't wait for the process to actually
# exit — with hwdec/heavy video, mpvpaper can take longer than a fixed sleep
# to release the layer-shell, and in that window two instances can share the
# GPU/decoder. Wait for real, up to 2 s in 100 ms steps, and SIGKILL whatever
# is still alive (mpvpaper isn't supervised by systemd: nothing else would
# clean it up).
kill_pids() {
    [ "$#" -gt 0 ] || return 0
    kill "$@" 2>/dev/null
    local waited=0 alive p
    while [ "$waited" -lt 20 ]; do
        alive=0
        for p in "$@"; do kill -0 "$p" 2>/dev/null && alive=1; done
        [ "$alive" -eq 0 ] && return 0
        sleep 0.1
        waited=$((waited + 1))
    done
    kill -9 "$@" 2>/dev/null
    return 0
}

start_video() {   # <output|*> <path>
    local log="$RUNTIME/mpvpaper.log" name="all"
    [ "$1" = "*" ] || { log="$RUNTIME/mpvpaper-$1.log"; name="$1"; }
    # 2026-09-26: mpv's IPC socket, so desktop-mode.sh can pause the video in
    # Gaming/Cinema (wallpaper-video-pause.sh); and a video started while one of
    # those modes is on starts paused. -p -a FULL: mpvpaper pauses on its own
    # while a fullscreen window hides the wallpaper, in any mode (it keeps a
    # pause set through IPC when the window goes away).
    local opts="$MPV_OPTS --input-ipc-server=$RUNTIME/sumi-mpvpaper-$name.sock"
    case "$(cat "${XDG_CACHE_HOME:-$HOME/.cache}/sumi-desktop-mode" 2>/dev/null)" in
        gaming|cinema) opts="$opts --pause" ;;
    esac
    # 2026-10-08 (portabilidad F4b): en su PROPIO scope de usuario. Lanzado desde la shell, un mpvpaper con
    # nohup/disown se quedaba en el cgroup de sumi-shell.service, y un restart de la shell (o una caída
    # con reinicio) se llevaba el vídeo de fondo (medido: KillMode=control-group). systemd-run --scope hace
    # exec de mpvpaper (mismo PID y mismo cmdline: mpv_instances sigue leyéndolo). Sin el gestor de usuario,
    # como antes. SUMI_WALL_UNIT_PREFIX sólo lo ponen las pruebas del banco (para no mezclar unidades).
    # setsid: fuera también del grupo de procesos de quien lo lanza (la shell). En un trabajo de fondo sin
    # control de trabajos no es líder de grupo, así que setsid no hace fork: el PID sigue siendo el de mpvpaper.
    local -a scope=()
    command -v setsid >/dev/null 2>&1 && scope=(setsid)
    if command -v systemd-run >/dev/null 2>&1 && [ -S "$RUNTIME/systemd/private" ]; then
        scope+=(systemd-run --user --scope --quiet --collect
               --unit "${SUMI_WALL_UNIT_PREFIX:-app-}hypr-mpvpaper-$name-$$-$RANDOM"
               -p PartOf=graphical-session.target -p TimeoutStopSec=3 --)
    fi
    # 9>&-: the lock's descriptor must not outlive this script. mpvpaper
    # inheriting it held the lock for as long as the video played.
    # <output> <path> stay the LAST two arguments: mpv_instances reads them there.
    nohup "${scope[@]}" mpvpaper -p -a FULL -o "$opts" "$1" "$2" >"$log" 2>&1 9>&- &
    disown
}

# ── awww ───────────────────────────────────────────────────────────────────

# The image awww shows on an output; "" if it shows a colour or nothing.
awww_showing() {
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^[^:]*:\ ([^:]+):.*currently\ displaying:\ image:\ (.*)$ ]] \
            && [ "${BASH_REMATCH[1]}" = "$1" ]; then
            printf '%s' "${BASH_REMATCH[2]}"
            return 0
        fi
    done < <(awww query 2>/dev/null)
}

# Transition for images (Sumi Shell 10B, 2026-09-26: Settings → Theme → Wallpaper →
# Transitions passes WALL_TRANSITION). Only awww's own names are accepted; anything else — or
# nothing, which is what wallpaper.service, the CLI and the hotplug sync send — is the
# historic "any". Videos (mpvpaper) have no transitions.
TRANSITION="${WALL_TRANSITION:-any}"
case "$TRANSITION" in
    none|simple|fade|left|right|top|bottom|wipe|wave|grow|center|any|outer|random) ;;
    *) TRANSITION=any ;;
esac

show_image() {   # <path> [output,output,...]; without outputs, every output
    local -a where=()
    [ -n "${2:-}" ] && where=(-o "$2")
    awww img "${where[@]}" "$1" --transition-type "$TRANSITION" --transition-fps 60 >/dev/null 2>&1
}

# ── Reconcile: make every output show what the state says ──────────────────

reconcile() {
    local global o w uniform=1
    global="$(global_wallpaper)"
    local -a outs=()
    mapfile -t outs < <(outputs)
    [ "${#outs[@]}" -gt 0 ] || die "no outputs (is Hyprland up?)"

    local -A want=()
    for o in "${outs[@]}"; do
        w="$(override_of "$o")"
        if [ -n "$w" ] && [ -f "$w" ]; then
            want[$o]="$w"
            [ "$w" = "$global" ] || uniform=0
        else
            want[$o]="$global"
        fi
    done

    if [ "$uniform" -eq 1 ]; then
        # The common case, and what the script always did: one mpvpaper on
        # '*' (it also covers outputs that appear later) or one awww image.
        local -a all=()
        mapfile -t all < <(mpv_pids '' '')
        if is_video "$global"; then
            local keep
            keep="$(mpv_pids '*' "$global" | head -n1)"
            if [ -n "$keep" ] && [ "${#all[@]}" -eq 1 ]; then
                return 0                                   # already on every output
            fi
            kill_pids "${all[@]}"
            start_video '*' "$global"
        else
            kill_pids "${all[@]}"
            local -a stale=()
            for o in "${outs[@]}"; do
                [ "$(awww_showing "$o")" = "$global" ] || stale+=("$o")
            done
            if [ "${#stale[@]}" -eq "${#outs[@]}" ]; then
                show_image "$global"
            elif [ "${#stale[@]}" -gt 0 ]; then
                show_image "$global" "$(IFS=,; printf '%s' "${stale[*]}")"
            fi
        fi
        return 0
    fi

    # Per output. A '*' instance would paint under every output's own one,
    # and one left on an output that is gone would just burn the decoder.
    local -a drop=()
    local pid out
    while IFS=$'\t' read -r pid out _; do
        if [ "$out" = "*" ] || [ -z "${want[$out]+x}" ]; then drop+=("$pid"); fi
    done < <(mpv_instances)
    kill_pids "${drop[@]}"

    local -a pids=()
    for o in "${outs[@]}"; do
        w="${want[$o]}"
        if is_video "$w"; then
            mapfile -t pids < <(mpv_pids "$o" "!$w")
            kill_pids "${pids[@]}"
            [ -n "$(mpv_pids "$o" "$w")" ] || start_video "$o" "$w"
        else
            mapfile -t pids < <(mpv_pids "$o" '')
            kill_pids "${pids[@]}"
            [ "$(awww_showing "$o")" = "$w" ] || show_image "$w" "$o"
        fi
    done
}

# ── Inheritance into hyprlock ───────────────────────────────────────────────

lock_background() {
    mkdir -p "$(dirname "$HYPRLOCK_BG")"
    if is_video "$1"; then
        if command -v ffmpeg >/dev/null 2>&1; then
            ffmpeg -y -ss 00:00:01 -i "$1" -vframes 1 -update 1 "$HYPRLOCK_BG" >>"$LOG" 2>&1 \
                || echo "$(date) WARN: couldn't extract frame for hyprlock from $1" >> "$LOG"
        else
            echo "$(date) WARN: ffmpeg not installed, hyprlock won't inherit this wallpaper" >> "$LOG"
        fi
    else
        # Normalized with ImageMagick (same binary generate-thumbs.sh
        # already uses) instead of a raw cp, so current.png's content is
        # a real PNG regardless of the source format.
        if command -v convert >/dev/null 2>&1; then
            convert "${1}[0]" "$HYPRLOCK_BG" >>"$LOG" 2>&1 || cp -f "$1" "$HYPRLOCK_BG" 2>>"$LOG"
        else
            cp -f "$1" "$HYPRLOCK_BG" 2>>"$LOG"
        fi
    fi
}

# ── Main ───────────────────────────────────────────────────────────────────

if [ "${1:-}" = "--sync" ]; then
    reconcile
    exit 0
fi

if [ "${1:-}" = "--clear" ]; then
    out="${2:-}"
    [ -n "$out" ] || die "--clear needs an output"
    if [ -f "$OUTPUTS_FILE" ]; then
        tmp="$(mktemp "$OUTPUTS_FILE.XXXXXX")" || die "can't write $OUTPUTS_FILE"
        awk -F'\t' -v o="$out" '$1 != o' "$OUTPUTS_FILE" > "$tmp"
        if [ -s "$tmp" ]; then mv -f "$tmp" "$OUTPUTS_FILE"; else rm -f "$tmp" "$OUTPUTS_FILE"; fi
    fi
    reconcile
    exit 0
fi

target="${1:-}"
MONITOR="${2:-${WALLPAPER_MONITOR:-}}"
restore=0

if [ -z "$target" ]; then
    # Restore: the persisted state as it is, per-output picks included.
    target="$(global_wallpaper)"
    MONITOR=""
    restore=1
    if [ -z "$target" ]; then
        # Fresh install: nothing picked yet and no default configured. Not an
        # error — wallpaper.service runs this on every login.
        echo "apply-wallpaper: no wallpaper chosen yet and SUMI_DEFAULT_WALLPAPER is unset; nothing to restore" >&2
        exit 0
    fi
fi

[ -f "$target" ] || die "wallpaper doesn't exist: $target"
is_video "$target" || is_image "$target" || die "unsupported extension: $target"

if [ -n "$MONITOR" ]; then
    mapfile -t outs < <(outputs)
    printf '%s\n' "${outs[@]}" | grep -qxF -- "$MONITOR" || die "no such output: $MONITOR"
    [ "${#outs[@]}" -eq 1 ] && MONITOR=""
fi

if [ -n "$MONITOR" ]; then
    set_override "$MONITOR" "$target"
    reconcile
    exit 0
fi

mkdir -p "$(dirname "$STATE_FILE")"
printf '%s' "$target" > "$STATE_FILE"
[ "$restore" -eq 1 ] || rm -f "$OUTPUTS_FILE"   # "every output" means every output
reconcile
lock_background "$target"
