#!/usr/bin/env bash
# ============================================================================
#  matugen_reload.sh — genera colores dinámicos (Minimaru) desde el
#  wallpaper actual y dispara los reloads correspondientes.
# ----------------------------------------------------------------------------
#  Llamado tras aplicar un wallpaper, con la ruta del archivo como $1: desde
#  Sumi Shell (services/Wallpaper.qml y scripts/apply-scheme), `minimaru wall`
#  / `minimaru theme`, wallpaper.service y matugen_toggle.sh. (wallpaper_grid.sh,
#  el picker de rofi que lo llamaba antes, se retiró en la Fase 10.e; este
#  script no, porque es la tubería de color — ADR-2.) Apagado por defecto — requiere el sentinel
#  $XDG_STATE_HOME/sumi-shell/theme/enabled (creado/borrado por matugen_toggle.sh), o la
#  variable de entorno ENABLE_DYNAMIC_COLORS=1 para pruebas manuales.
#
#  matugen solo acepta imágenes estáticas — si el wallpaper es un video
#  (mp4/mkv/mov/webm, el caso por defecto de este rice vía mpvpaper), se
#  extrae un frame con ffmpeg antes de generar colores.
#
#  Los reloads por-app (kitty → SIGUSR1, Hyprland → hyprctl
#  eval) ya NO se manejan acá — cada uno es un post_hook de su template en
#  ~/.config/matugen/config.toml. Este script solo resuelve el frame de
#  entrada y llama a matugen; todo lo demás lo dispara matugen solo.
#
#  Esquema de color: antes hardcodeado a "scheme-tonal-spot". Ahora se lee de
#  ~/.config/matugen/scheme (una línea, sin saltos) si existe — así el
#  selector de perfil (la superficie `theme` del shell, o `minimaru theme
#  <esquema>`; antes rofi/scripts/theme.sh) puede cambiarlo sin tocar este script. Sin ese
#  archivo, cae al mismo default de siempre (tonal-spot), cero cambio de
#  comportamiento para quien no use el selector de perfiles.
#
#  Rediseño 12F (2026-09-28): tres ajustes más junto a `scheme`, cada uno en su archivo de una
#  línea, con lista blanca y default si falta o trae basura (mismo criterio que el esquema):
#    ~/.config/matugen/mode       dark | light                       (default dark)
#    ~/.config/matugen/contrast   -1 … 1, hasta dos decimales        (default 0: sin --contrast)
#    ~/.config/matugen/source     wallpaper | #rrggbb                (default wallpaper)
#  Con un color de origen, la paleta sale de ese color (`matugen color hex`), no del fondo: el
#  fondo deja de hacer falta. Los escribe el shell al confirmar una preview (Keep changes).
# ============================================================================

set -u
set -o pipefail

WALL="${1:-}"
LOG="${XDG_RUNTIME_DIR:-/tmp}/matugen-reload.log"
FRAME="${XDG_RUNTIME_DIR:-/tmp}/matugen-frame.png"

THEME_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sumi-shell/theme"
MATUGEN_CONFIG="${MATUGEN_CONFIG:-$HOME/.config/matugen/config.toml}"
MATUGEN_SENTINEL="${MATUGEN_SENTINEL:-$THEME_DIR/enabled}"
MATUGEN_SCHEME_FILE="${MATUGEN_SCHEME_FILE:-$THEME_DIR/scheme}"
ENABLE_DYNAMIC_COLORS="${ENABLE_DYNAMIC_COLORS:-0}"
MATUGEN_MODE_FILE="${MATUGEN_MODE_FILE:-$THEME_DIR/mode}"
MATUGEN_CONTRAST_FILE="${MATUGEN_CONTRAST_FILE:-$THEME_DIR/contrast}"
MATUGEN_SOURCE_FILE="${MATUGEN_SOURCE_FILE:-$THEME_DIR/source}"

# Whitelist — misma lista que reporta `matugen --help`. Si el archivo trae
# basura (edición a mano, corrupción), cae al default en vez de pasarle un
# -t inválido a matugen.
VALID_SCHEMES="scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow scheme-tonal-spot scheme-vibrant"
MATUGEN_SCHEME="scheme-tonal-spot"
if [ -f "$MATUGEN_SCHEME_FILE" ]; then
    candidate="$(tr -d '[:space:]' < "$MATUGEN_SCHEME_FILE" 2>/dev/null)"
    for s in $VALID_SCHEMES; do
        if [ "$s" = "$candidate" ]; then
            MATUGEN_SCHEME="$candidate"
            break
        fi
    done
fi

MATUGEN_MODE="dark"
if [ -f "$MATUGEN_MODE_FILE" ]; then
    candidate="$(tr -d '[:space:]' < "$MATUGEN_MODE_FILE" 2>/dev/null)"
    [ "$candidate" = "light" ] && MATUGEN_MODE="light"
fi
CONTRAST_ARGS=()
if [ -f "$MATUGEN_CONTRAST_FILE" ]; then
    candidate="$(tr -d '[:space:]' < "$MATUGEN_CONTRAST_FILE" 2>/dev/null)"
    # -1 … 1 con hasta dos decimales; 0 = el diseño estándar (no se pasa)
    if [[ "$candidate" =~ ^-?(0(\.[0-9]{1,2})?|1(\.0{1,2})?)$ ]] && [ "$candidate" != "0" ]; then
        CONTRAST_ARGS=(--contrast "$candidate")
    fi
fi
SOURCE_HEX=""
if [ -f "$MATUGEN_SOURCE_FILE" ]; then
    candidate="$(tr -d '[:space:]' < "$MATUGEN_SOURCE_FILE" 2>/dev/null)"
    [[ "$candidate" =~ ^#[0-9a-fA-F]{6}$ ]] && SOURCE_HEX="$candidate"
fi

echo "$(date) === matugen_reload START (wall=$WALL mode=$MATUGEN_MODE contrast=${CONTRAST_ARGS[1]:-0} source=${SOURCE_HEX:-wallpaper}) ===" >> "$LOG"

# ── Gate: ¿está encendido el theming dinámico? ───────────────────────────────
if [ "$ENABLE_DYNAMIC_COLORS" != "1" ] && [ ! -f "$MATUGEN_SENTINEL" ]; then
    echo "$(date) dinámico apagado (sin sentinel ni ENABLE_DYNAMIC_COLORS) — nada que hacer" >> "$LOG"
    exit 0
fi

command -v matugen >/dev/null 2>&1 || { echo "$(date) matugen no instalado — abortando" >> "$LOG"; exit 0; }

# F1a: matugen no expande variables de entorno en output_path. Config temporal
# con las mismas salidas y hooks, resolviendo sólo la ruta de estado de Minimaru.
SHELL_DIR="${SUMI_SHELL_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/sumi}"
RESOLVED_CONFIG="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/sumi-matugen.XXXXXX.toml")" || exit 1
trap 'rm -f -- "$RESOLVED_CONFIG"' EXIT
if ! python3 -B "$SHELL_DIR/scripts/theme_paths.py" "$MATUGEN_CONFIG" > "$RESOLVED_CONFIG" 2>>"$LOG"; then
    echo "$(date) no se pudo resolver la configuración de matugen" >> "$LOG"
    exit 1
fi
MATUGEN_CONFIG="$RESOLVED_CONFIG"


# ── Color de origen propio: la paleta no depende del fondo ───────────────────
if [ -n "$SOURCE_HEX" ]; then
    if matugen --config "$MATUGEN_CONFIG" color hex "$SOURCE_HEX" -m "$MATUGEN_MODE" -t "$MATUGEN_SCHEME" "${CONTRAST_ARGS[@]}" >>"$LOG" 2>&1; then
        echo "$(date) matugen OK (color: $SOURCE_HEX, scheme: $MATUGEN_SCHEME)" >> "$LOG"
    else
        echo "$(date) matugen falló generando templates — los archivos anteriores quedan intactos" >> "$LOG"
    fi
    echo "$(date) === matugen_reload END ===" >> "$LOG"
    exit 0
fi

[ -n "$WALL" ] && [ -f "$WALL" ] || { echo "$(date) wallpaper vacío o inexistente — abortando" >> "$LOG"; exit 0; }

# ── Resolver imagen de entrada: extraer frame si es video ────────────────────
ext="${WALL##*.}"
ext="${ext,,}"

case "$ext" in
    mp4|mkv|mov|webm)
        command -v ffmpeg >/dev/null 2>&1 || { echo "$(date) ffmpeg no instalado, no se puede extraer frame de video — abortando" >> "$LOG"; exit 0; }
        if ! ffmpeg -y -ss 00:00:01 -i "$WALL" -vframes 1 -update 1 "$FRAME" >>"$LOG" 2>&1; then
            echo "$(date) fallo extrayendo frame de $WALL — abortando" >> "$LOG"
            exit 0
        fi
        IN="$FRAME"
        ;;
    *)
        IN="$WALL"
        ;;
esac

# ── Generar colores (los post_hook de cada template disparan sus reloads) ───
if matugen --config "$MATUGEN_CONFIG" image "$IN" -m "$MATUGEN_MODE" -t "$MATUGEN_SCHEME" "${CONTRAST_ARGS[@]}" >>"$LOG" 2>&1; then
    echo "$(date) matugen OK (imagen: $IN, scheme: $MATUGEN_SCHEME)" >> "$LOG"
else
    echo "$(date) matugen falló generando templates — los archivos anteriores quedan intactos" >> "$LOG"
fi
echo "$(date) === matugen_reload END ===" >> "$LOG"
