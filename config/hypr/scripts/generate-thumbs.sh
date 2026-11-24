#!/usr/bin/env bash
# ============================================================================
#  generate-thumbs.sh — genera thumbnails para el wallpaper picker
#  Imágenes : convert (ImageMagick)
#  Videos   : ffmpegthumbnailer
# ============================================================================

set -u
set -o pipefail

WALLPAPER_DIR_VIDEO="${WALLPAPER_DIR_VIDEO:-$HOME/Videos/Wallpapers}"
WALLPAPER_DIR_IMG="${WALLPAPER_DIR_IMG:-$HOME/Pictures/Wallpapers}"
THUMB_DIR="${THUMB_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/sumi-wallpapers/thumbs}"
THUMB_SIZE="${THUMB_SIZE:-320}"   # ancho del thumbnail en píxeles
LOG="${XDG_RUNTIME_DIR:-/tmp}/rofi-wallpaper-gen.log"
LOCK_FILE="$THUMB_DIR/.generate.lock"
# Rediseño 10A (2026-09-26): las carpetas de Theme → Wallpaper → Sources. Sumi Shell escribe
# aquí una ruta absoluta por línea; con la lista, cada carpeta aporta imágenes Y vídeos (el tipo
# lo da la extensión, como en el shell). Sin la lista, lo de siempre: las dos carpetas fijas.
SOURCES_FILE="${WALLPAPER_SOURCES_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/sumi-shell/wallpaper-sources}"
SOURCES=()
if [ -f "$SOURCES_FILE" ]; then
    while IFS= read -r d || [ -n "$d" ]; do
        [ -n "$d" ] && SOURCES+=("$d")
    done < "$SOURCES_FILE"
    USE_LIST=1
else
    USE_LIST=0
fi

mkdir -p "$THUMB_DIR"

# wallpaper_rofi.sh relanza este script en background cada vez que detecta
# wallpapers más nuevos que ".last-scan" — pero ese marker solo se escribe
# al FINAL de un escaneo completo. Sin este lock, reabrir el picker mientras
# una librería grande todavía se está escaneando dispara un segundo
# escaneo completo encima del primero (confirmado en vivo: dos
# generate-thumbs.sh corriendo a la vez, cada uno con su propio `convert`
# reprocesando los mismos archivos nuevos) — CPU/IO se duplica por cada
# reapertura impaciente en vez de sumarse una sola vez. `flock -n` hace que
# la segunda instancia salga al toque en vez de competir por los mismos
# archivos; la primera termina su escaneo tranquila y deja el marker
# actualizado para todos.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "$(date) generate-thumbs.sh: ya hay un escaneo corriendo, salgo" >> "$LOG"
    exit 0
fi

generated=0
skipped=0
errors=0
# Las miniaturas se nombran por el archivo, sin la carpeta: con varias carpetas en Sources, dos
# archivos con el mismo nombre compartirían una. La primera en el orden de Sources se la queda y
# los repetidos no la pisan (el shell avisa de ellos en Sources). Medido en la 10A: sin esto, una
# carpeta de prueba con otro «wallpaper.png» sobrescribió la miniatura del fondo del usuario.
declare -A SEEN=()

process_image() {
    local src="$1"
    local thumb name
    name="$(basename "$src")"
    [ -n "${SEEN[$name]:-}" ] && { skipped=$((skipped + 1)); return 0; }
    SEEN[$name]=1
    thumb="$THUMB_DIR/$name.jpg"

    # "-nt" (más nuevo que) en vez de solo existencia: si el wallpaper se
    # reemplaza con el mismo nombre pero contenido distinto, el thumbnail
    # viejo quedaba para siempre porque nunca se comparaba mtime.
    [ -f "$thumb" ] && [ "$thumb" -nt "$src" ] && { skipped=$((skipped + 1)); return 0; }

    if convert "${src}[0]" \
        -thumbnail "${THUMB_SIZE}x" \
        -quality 85 \
        "$thumb" >>"$LOG" 2>&1; then
        generated=$((generated + 1))
    else
        echo "$(date) ERROR imagen: $src" >> "$LOG"
        errors=$((errors + 1))
    fi
}

process_video() {
    local src="$1"
    local thumb name
    name="$(basename "$src")"
    [ -n "${SEEN[$name]:-}" ] && { skipped=$((skipped + 1)); return 0; }
    SEEN[$name]=1
    thumb="$THUMB_DIR/$name.jpg"

    [ -f "$thumb" ] && [ "$thumb" -nt "$src" ] && { skipped=$((skipped + 1)); return 0; }

    if ffmpegthumbnailer \
        -i "$src" \
        -o "$thumb" \
        -s "$THUMB_SIZE" \
        -q 8 \
        -t 10% \
        >>"$LOG" 2>&1; then
        generated=$((generated + 1))
    else
        echo "$(date) ERROR video: $src" >> "$LOG"
        errors=$((errors + 1))
    fi
}

echo "$(date) === generate-thumbs START ===" >> "$LOG"

scan_dir() {
    # $1 carpeta, $2 "img" | "vid" | "all"
    [ -d "$1" ] || return 0
    shopt -s nullglob nocaseglob
    if [ "$2" != vid ]; then
        for f in "$1"/*.{jpg,jpeg,png,webp,gif}; do
            [ -f "$f" ] && process_image "$f"
        done
    fi
    if [ "$2" != img ]; then
        for f in "$1"/*.{mp4,mkv,mov,webm}; do
            [ -f "$f" ] && process_video "$f"
        done
    fi
    shopt -u nullglob nocaseglob
}

if [ "$USE_LIST" = 1 ]; then
    for d in "${SOURCES[@]}"; do scan_dir "$d" all; done
else
    # ── Imágenes y vídeos, cada tipo en su carpeta (sin lista) ──
    scan_dir "$WALLPAPER_DIR_IMG" img
    scan_dir "$WALLPAPER_DIR_VIDEO" vid
fi

# ── Poda: thumbnails sin wallpaper vivo ──────────────────────────────────────
# El nombre de cada thumbnail es "<nombre-original-con-extensión>.jpg" (ver
# process_image/process_video), así que basta con despojar el ".jpg" final
# y comprobar que ese nombre exista como archivo real en alguna de las
# carpetas de wallpapers (la lista de Sources, o las dos de siempre) — si no, el thumbnail quedó huérfano (wallpaper
# borrado o renombrado) y se borra.
pruned=0
if [ -d "$THUMB_DIR" ]; then
    shopt -s nullglob
    for thumb in "$THUMB_DIR"/*.jpg; do
        [ -f "$thumb" ] || continue
        src_name="$(basename "$thumb" .jpg)"
        alive=0
        if [ "$USE_LIST" = 1 ]; then
            for d in "${SOURCES[@]}"; do
                [ -f "$d/$src_name" ] && { alive=1; break; }
            done
        else
            { [ -f "$WALLPAPER_DIR_IMG/$src_name" ] || [ -f "$WALLPAPER_DIR_VIDEO/$src_name" ]; } && alive=1
        fi
        if [ "$alive" = 0 ]; then
            rm -f "$thumb"
            pruned=$((pruned + 1))
        fi
    done
    shopt -u nullglob
fi

echo "$(date) === generate-thumbs END | generados=$generated saltados=$skipped errores=$errors podados=$pruned ===" >> "$LOG"

# Marca de "último escaneo completo" — wallpaper_rofi.sh la usa para saltarse
# el escaneo por completo cuando no hay wallpapers nuevos desde la última vez.
touch "$THUMB_DIR/.last-scan"