#!/usr/bin/env bash
# ============================================================================
#  check-config-drift.sh — informational check (blocks nothing) for the class
#  of bug that dotbackup's sync direction makes easy to create: a reference
#  in one file that quietly stops matching reality in another.
#
#  Why this exists: dotbackup syncs ~/.config INTO the repo, so config changes
#  land as "dotfiles: backup <date>" commits with no stated intent. Nothing
#  compares the pieces against each other, so a half-finished migration can
#  sit broken for days. That is exactly what happened to the GTK layer in
#  August 2026 — matugen kept generating gtk-colors.css after nothing imported
#  it any more, theme-base.css was left dangling at a deleted theme, and the
#  icon theme drifted apart between GTK and Qt/Rofi. Every one of those was
#  mechanically detectable; nothing was looking.
#
#  Companion to check-template-parity.sh (same idiom: silent on success,
#  exit code = number of problems, surfaced by `minimaru doctor`). That one
#  checks the INSIDE of the color files; this one checks the wiring BETWEEN
#  files.
#
#  Seven checks:
#    1. every @import in gtk.css resolves, and gtk.css isn't an nwg-look symlink
#    2. CursorTheme / GTKTheme name directories that actually exist
#    3. the four places that hardcode the icon theme agree
#    4. every file matugen generates has something that loads it
#    5. no broken symlinks in the config dirs this repo owns
#    6. the lockscreen chain (Sumi Shell's lock design, ADR-30): lock.sh
#       exists and is executable, hypridle.conf actually calls it and keeps
#       inhibit_sleep, Hyprland has the two options the lock needs, the
#       rescue unit exists and is wired into sumi-shell.service, and
#       hyprlock — the lock's own safety net — is still installed
#    7. what Fases 10.e (rofi's menus), 11 (Waybar, wlogout) and 4 (SwayNC)
#       retired stays retired: none of it came back, and nothing live still
#       calls one
# ============================================================================
set -u

# Overridable so the checks can be exercised against a fixture tree instead of
# the live config — that is how this script's own failure modes were verified.
BASE="${MINIMARU_CONFIG_DIR:-$HOME/.config}"
problems=0

warn() {
    echo "  ⚠ $*"
    problems=$((problems + 1))
}
detail() { echo "      $*"; }

# Config dirs this repo publishes. Used to scope the searches so unrelated
# things under ~/.config (VSCodium's edit history, browser caches) can't
# create noise — that history in particular mentions every color file this
# rice has ever had, which would make check 4 useless.
REPO_DIRS=(cava fastfetch fish gtk-3.0 gtk-4.0 hypr hyprlock kitty matugen
           qt5ct qt6ct quickshell systemd)

# ── 1. gtk.css: imports resolve, and the file is still ours ─────────────────
# gtk.css is a one-line "@import 'gtk-colors.css';" on both sides. nwg-look
# replaces it with a symlink to whatever GTK4 theme you pick in its GUI, which
# silently drops the color overlay — and dotbackup then follows the symlink and
# commits the theme's whole stylesheet into the repo.
for gtkdir in gtk-3.0 gtk-4.0; do
    css="$BASE/$gtkdir/gtk.css"

    # -L before -f on purpose: -f follows the link, so a symlink pointing at a
    # theme file that has since been uninstalled would otherwise be reported as
    # "doesn't exist" and bury the far more useful "nwg-look replaced this".
    if [ -L "$css" ]; then
        warn "gtk.css — $gtkdir/gtk.css is a symlink, not a real file"
        detail "-> $(readlink "$css")"
        [ -e "$css" ] || detail "(and the target no longer exists)"
        detail "nwg-look does this. Restore it with:"
        detail "printf \"@import 'gtk-colors.css';\\n\" > ~/.config/$gtkdir/gtk.css"
        continue
    fi

    if [ ! -f "$css" ]; then
        warn "gtk.css — $gtkdir/gtk.css doesn't exist"
        continue
    fi

    imports="$(grep -oP "@import\s+['\"]\K[^'\"]+" "$css" 2>/dev/null || true)"

    if [ -z "$imports" ]; then
        warn "gtk.css — $gtkdir/gtk.css has no @import"
        detail "it should pull in gtk-colors.css, or the palette never loads"
        continue
    fi

    while IFS= read -r imp; do
        [ -n "$imp" ] || continue
        case "$imp" in
            /*)  target="$imp" ;;
            \~*) target="$HOME${imp#\~}" ;;
            *)   target="$BASE/$gtkdir/$imp" ;;
        esac
        if [ ! -e "$target" ]; then
            warn "gtk.css — $gtkdir/gtk.css imports '$imp', which doesn't exist"
            detail "expected at: $target"
            detail "run: bash ~/.config/hypr/scripts/apply-static-colors.sh"
        fi
    done <<< "$imports"
done

# ── 2. Theme names point at directories that exist ──────────────────────────
# XCURSOR and GTK both match on the theme's DIRECTORY name and both are
# case-sensitive, so a theme renamed, uninstalled or capitalised differently
# fails silently: you just get the default arrow / the default theme.
ENV_LUA="$BASE/hypr/modules/environment.lua"
if [ -f "$ENV_LUA" ]; then
    cursor_theme="$(grep -oP '^CursorTheme\s*=\s*"\K[^"]+' "$ENV_LUA" 2>/dev/null || true)"
    gtk_theme="$(grep -oP '^GTKTheme\s*=\s*"\K[^"]+' "$ENV_LUA" 2>/dev/null || true)"

    if [ -n "$cursor_theme" ]; then
        found=""
        for d in /usr/share/icons "$HOME/.icons" "$HOME/.local/share/icons"; do
            [ -d "$d/$cursor_theme" ] && { found="$d/$cursor_theme"; break; }
        done
        if [ -z "$found" ]; then
            warn "CursorTheme — '$cursor_theme' isn't installed anywhere"
            detail "looked in /usr/share/icons, ~/.icons, ~/.local/share/icons"
            detail "the name must be the theme's DIRECTORY, and it is case-sensitive"
        fi
    fi

    if [ -n "$gtk_theme" ]; then
        found=""
        for d in /usr/share/themes "$HOME/.themes" "$HOME/.local/share/themes"; do
            [ -d "$d/$gtk_theme" ] && { found="$d/$gtk_theme"; break; }
        done
        if [ -z "$found" ]; then
            warn "GTKTheme — '$gtk_theme' isn't installed anywhere"
            detail "looked in /usr/share/themes, ~/.themes, ~/.local/share/themes"
        fi
    fi
fi

# ── 3. The icon theme is spelled the same in all four places ────────────────
# Two of the four (the settings.ini files) are written by nwg-look and are NOT
# versioned, so they're the ones most likely to drift away from the two the
# repo does ship. When they disagree, GTK apps and Qt show different sets.
# (There were five: rofi/window-switcher.rasi hardcoded it too, until Fase 10.e
# retired the window switcher. Check 7 makes sure it stays gone.)
declare -a icon_names=() icon_where=()
add_icon() { [ -n "$2" ] && { icon_names+=("$2"); icon_where+=("$1"); }; }

for gtkdir in gtk-3.0 gtk-4.0; do
    ini="$BASE/$gtkdir/settings.ini"
    if [ -f "$ini" ]; then
        add_icon "$gtkdir/settings.ini" \
            "$(grep -oP '^gtk-icon-theme-name\s*=\s*\K.*' "$ini" 2>/dev/null | tr -d '\r' || true)"
    else
        warn "icon theme — $gtkdir/settings.ini not found"
        detail "nwg-look writes it and it isn't versioned; until it exists,"
        detail "GTK apps use the default icon theme while Qt apps use their own"
    fi
done

for qt in qt5ct qt6ct; do
    conf="$BASE/$qt/$qt.conf"
    [ -f "$conf" ] && add_icon "$qt/$qt.conf" \
        "$(grep -oP '^icon_theme\s*=\s*\K.*' "$conf" 2>/dev/null | tr -d '\r' || true)"
done

if [ "${#icon_names[@]}" -gt 0 ]; then
    unique="$(printf '%s\n' "${icon_names[@]}" | sort -u)"
    if [ "$(printf '%s\n' "$unique" | wc -l)" -gt 1 ]; then
        warn "icon theme — the hardcoded names disagree"
        for i in "${!icon_names[@]}"; do
            detail "$(printf '%-28s %s' "${icon_where[$i]}" "${icon_names[$i]}")"
        done
        detail "all of them have to match or GTK and Qt render different sets"
    else
        # They agree — but does the theme exist?
        theme="$(printf '%s' "$unique")"
        found=""
        for d in /usr/share/icons "$HOME/.icons" "$HOME/.local/share/icons"; do
            [ -d "$d/$theme" ] && { found="$d/$theme"; break; }
        done
        [ -z "$found" ] && {
            warn "icon theme — '$theme' is set everywhere but isn't installed"
            detail "looked in /usr/share/icons, ~/.icons, ~/.local/share/icons"
        }
    fi
fi

# ── 4. Everything matugen generates has a consumer ──────────────────────────
# The GTK bug in one line: matugen kept writing gtk-colors.css long after the
# @import that loaded it was gone. A generated file nobody reads is dead
# weight at best and a silently-broken feature at worst.
#
# "Consumer" = a non-comment line naming the file, inside the dirs above,
# excluding the file itself, the *.static.* mirrors, and the two scripts that
# WRITE these files (apply-static-colors.sh mentions every single one of them,
# so counting it would make this check always pass). config.toml's own
# input_path/output_path lines are excluded for the same reason — they name
# every output by construction, which silently made this check a no-op until
# it was tested against a known-broken tree. Its post_hook lines DO count:
# running a generated file is a legitimate way to consume it.
#
# Known limit: the match is by basename, so outputs that share one can mask
# each other — waybar/, swaync/ and wlogout/ all generated a "colors.css", and
# any one of the three kept the other two looking alive. Verified back then:
# commenting out waybar's @import was NOT caught. The three are gone (Fases 10,
# 11 y 4), so today only gtk-3.0/gtk-4.0 share a basename — the limit stands as
# a warning for the next one. What this check does catch is a file with
# no readers anywhere, which is the failure mode that actually happened (the
# GTK one, whose basename is unique). Narrowing it to per-directory matching
# was tried and rejected: hyprlock/colors.conf is loaded from hypr/hyprlock.conf
# as "source = $hyprlockDir/colors.conf", so a directory-scoped or
# path-literal match reports it as orphaned when it isn't.
MATUGEN_CONF="$BASE/matugen/config.toml"

# Loaded by convention, not by reference — no file can name these, so an
# absence of references is correct and must not be reported.
is_convention_loaded() {
    case "$1" in
        starship.toml)      return 0 ;;  # starship reads ~/.config/starship.toml by name
        theme-goldship.fish) return 0 ;; # fish sources every conf.d/*.fish on shell start
        *) return 1 ;;
    esac
}

if [ -f "$MATUGEN_CONF" ]; then
    outputs="$(grep -oP "output_path\s*=\s*'\K[^']+" "$MATUGEN_CONF" 2>/dev/null || true)"

    search_paths=()
    for d in "${REPO_DIRS[@]}"; do
        [ -d "$BASE/$d" ] && search_paths+=("$BASE/$d")
    done

    while IFS= read -r out; do
        [ -n "$out" ] || continue
        out_abs="${out/#\~/$HOME}"
        rel="${out_abs#"$HOME"/.config/}"   # display only; config.toml holds absolute paths
        base_name="$(basename "$out_abs")"

        is_convention_loaded "$base_name" && continue

        hits="$(grep -rIn --fixed-strings "$base_name" "${search_paths[@]}" 2>/dev/null \
                | grep -v "^$out_abs:" \
                | grep -v '\.static\.' \
                | grep -v 'apply-static-colors\.sh:' \
                | grep -v 'check-template-parity\.sh:' \
                | grep -v 'check-config-drift\.sh:' \
                | grep -vP ':\s*[0-9]+:\s*(#|//|--|/\*|\*)' \
                | grep -vP ':\s*[0-9]+:\s*(input_path|output_path)\s*=' \
                | head -1 || true)"

        if [ -z "$hits" ]; then
            warn "matugen output — nothing loads '$rel'"
            detail "matugen regenerates it on every wallpaper change, but no"
            detail "@import / include / source in the config refers to it"
        fi
    done <<< "$outputs"
fi

# ── 5. No broken symlinks in the dirs this repo owns ────────────────────────
# theme-base.css spent weeks pointing at a ~/.themes/ entry that had been
# deleted. Nothing complained because nothing read it any more — but a dangling
# symlink is always either a leftover or a genuinely broken load.
dangling=""
for d in "${REPO_DIRS[@]}"; do
    [ -d "$BASE/$d" ] || continue
    found="$(find "$BASE/$d" -xtype l 2>/dev/null || true)"
    [ -n "$found" ] && dangling+="$found"$'\n'
done

if [ -n "${dangling%$'\n'}" ]; then
    warn "broken symlinks in the config dirs"
    while IFS= read -r l; do
        [ -n "$l" ] || continue
        detail "$(printf '%-45s -> %s' "${l#"$BASE"/}" "$(readlink "$l")")"
    done <<< "${dangling%$'\n'}"
fi


# ── 6. The lockscreen chain (ADR-30) ─────────────────────────────────────────
LOCK_SH="$BASE/hypr/scripts/lock.sh"
if [ ! -x "$LOCK_SH" ]; then
    warn "lockscreen — hypr/scripts/lock.sh missing or not executable"
    detail "expected at: $LOCK_SH"
else
    IDLE_CONF="$BASE/hypr/hypridle.conf"
    if [ -f "$IDLE_CONF" ]; then
        grep -q "lock_cmd.*lock\.sh" "$IDLE_CONF" || {
            warn "lockscreen — hypridle.conf's lock_cmd doesn't call lock.sh"
            detail "the shell's own lock would never run; hypridle would fall straight to hyprlock"
        }
        grep -q "inhibit_sleep" "$IDLE_CONF" || {
            warn "lockscreen — hypridle.conf has no inhibit_sleep"
            detail "without it (R3), the machine could suspend before the screen locks"
        }
    else
        warn "lockscreen — hypridle.conf not found"
    fi
fi

if command -v hyprctl >/dev/null 2>&1; then
    for opt in allow_session_lock_restore session_lock_xray; do
        val="$(hyprctl getoption "misc:$opt" -j 2>/dev/null | grep -oP '"set":\s*\K(true|false)' || true)"
        [ "$val" = "true" ] || {
            warn "lockscreen — misc:$opt isn't set to true"
            detail "check hypr/modules/misc.lua"
        }
    done
fi

RESCUE_UNIT="$BASE/systemd/user/sumi-lock-rescue.service"
SHELL_UNIT="$BASE/systemd/user/sumi-shell.service"
if [ ! -f "$RESCUE_UNIT" ]; then
    warn "lockscreen — sumi-lock-rescue.service not found"
    detail "expected at: $RESCUE_UNIT"
elif [ -f "$SHELL_UNIT" ]; then
    grep -q "^OnFailure=sumi-lock-rescue.service" "$SHELL_UNIT" || \
        warn "lockscreen — sumi-shell.service doesn't name the rescue unit in OnFailure="
    # Desde F5 la unidad pide el rescate por `sumi-lock rescue-request` (no lo lanza si ExecCondition saltó la
    # unidad); el helper arranca sumi-lock-rescue.service. Valen las dos formas.
    grep -qE "^ExecStopPost=.*(sumi-lock-rescue\.service|sumi-lock rescue-request)" "$SHELL_UNIT" || \
        warn "lockscreen — sumi-shell.service doesn't start the rescue unit in ExecStopPost="
fi

command -v hyprlock >/dev/null 2>&1 || {
    warn "lockscreen — hyprlock isn't installed"
    detail "it's the lock's safety net (ADR-30): the shell falls back to it if it can't lock itself"
}

# ── 7. What Fases 10.e, 11 and 4 retired stays retired ──────────────────────
# Fase 10.e (2026-09-17) retired rofi's menus, Fase 11 (2026-09-21) Waybar and
# wlogout, and the notifications Fase 4 (2026-09-22) SwayNC, whose package is
# uninstalled too — Sumi Shell has a surface for each (Quickshell/docs/MIGRATION.md
# §«Sub-fase 10.e» and §«Fase 11», with the way back for every file). Their
# ABSENCE is the expected state; this reports the two ways that goes wrong:
#   a) something live still calls a retired file — a keybind, a fish function,
#      a systemd unit, the shell — and fails silently the day it's used;
#   b) a retired file came back (a rollback, a restore from the repo) without
#      this list and MIGRATION.md being told.
# Nothing of rofi's is left under ~/.config: what was never rofi's UI moved out
# with it in Fase 11 — the colour pipeline (generate-thumbs.sh, matugen_reload.sh,
# matugen_toggle.sh — ADR-2) and websites.conf now live in hypr/, and Waybar's
# updates.sh in hypr/scripts/ too, because the shell, its timer and the update
# notice all read its cache. So the whole rofi/ directory has to stay gone.
RETIRED_ROFI=(
    launcher.sh
    scripts/audio.sh scripts/bluetooth.sh scripts/dashboard.sh scripts/mode.sh
    scripts/mpris.sh scripts/power.sh scripts/systemd.sh scripts/theme.sh
    scripts/wallpaper_grid.sh scripts/wallpaper_launcher.sh
    scripts/wallpaper_rofi.sh scripts/web_category.sh scripts/web_common.sh
    scripts/web_launcher.sh scripts/web_picker.sh scripts/wifi.sh
    scripts/window-switcher.sh
    clipboard.rasi style-4.rasi wallpaper-picker.rasi wallpaper-type-select.rasi
    web-hub.rasi window-switcher.rasi
)
# Fases 11 y 4: directorios y archivos enteros, no piezas sueltas. `swaync/` se
# conservó en disco durante toda la Fase 3 a propósito (era la vuelta atrás); la
# Fase 4 lo borró junto con el paquete, así que su reaparición ya es una señal.
RETIRED_TREES=(waybar wlogout rofi swaync)
RETIRED_FILES=(
    systemd/user/waybar.service systemd/user/playerctl-watch.service
    systemd/user/swaync.service
    matugen/templates/waybar-colors.css matugen/templates/wlogout-colors.css
    matugen/templates/swaync-colors.css
)

back=""
for f in "${RETIRED_ROFI[@]}"; do
    [ -e "$BASE/rofi/$f" ] && back+="rofi/$f"$'\n'
done
for d in "${RETIRED_TREES[@]}"; do
    [ -e "$BASE/$d" ] && back+="$d/"$'\n'
done
for f in "${RETIRED_FILES[@]}"; do
    [ -e "$BASE/$f" ] && back+="$f"$'\n'
done
if [ -n "$back" ]; then
    warn "retired pieces — something retired in Fase 10.e, 11 or 4 is back"
    while IFS= read -r l; do [ -n "$l" ] && detail "$l"; done <<< "${back%$'\n'}"
    detail "if you rolled one back on purpose, drop it from the RETIRED_* lists"
    detail "here and from the tables in Quickshell/docs/MIGRATION.md"
    detail "(SwayNC also needs its package back: it was uninstalled in Fase 4)"
fi

ref_dirs=()
for d in "${REPO_DIRS[@]}"; do
    [ -d "$BASE/$d" ] && ref_dirs+=("$BASE/$d")
done

# One regex for all of them: `rofi/scripts/wifi.sh`, `rofi/launcher.sh`, … in
# whatever form the caller spells the prefix ($HOME/.config/, ~/.config/, $dir/).
alt=""
for f in "${RETIRED_ROFI[@]}"; do alt+="${alt:+|}${f//./\\.}"; done
# Comment lines are skipped — history names these files everywhere, on purpose
# (#, --, //, and the * of a /** */ block). Prose files too.
calls=""
if [ "${#ref_dirs[@]}" -gt 0 ]; then
    calls="$(grep -rInE "rofi/($alt)([^A-Za-z0-9_.-]|\$)" "${ref_dirs[@]}" \
                 --exclude='*.md' --exclude='*.txt' --exclude-dir=.git 2>/dev/null \
             | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|--|//|/?\*)' || true)"
fi
# Fase 11: una ruta dentro de waybar/ o wlogout/, su unidad, o un systemctl /
# pkill que las nombre. La ruta tiene que venir precedida de `/`, `$`, `~` o
# comilla — o sea, usada como ruta: sin eso, cualquier "que usa waybar/x.sh" en
# medio de un comentario de varias lineas (CSS, docstring de Python) se cuela,
# porque el filtro de comentarios de abajo solo mira el principio de la linea.
# Y este script se excluye a si mismo: las listas de arriba las nombran todas.
calls11=""
if [ "${#ref_dirs[@]}" -gt 0 ]; then
    calls11="$(grep -rInE '[/"'"'"'$~](waybar|wlogout)/[A-Za-z0-9_./-]+|(waybar|playerctl-watch)\.service|(systemctl|pkill|pgrep)[^;&|]*\b(waybar|wlogout|playerctl-watch)\b' \
                 "${ref_dirs[@]}" --exclude='*.md' --exclude='*.txt' --exclude-dir=.git \
                 --exclude='check-config-drift.sh' 2>/dev/null \
               | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|--|//|/?\*)' || true)"
fi
if [ -n "$calls11" ]; then
    warn "retired pieces — something live still calls Waybar or wlogout"
    while IFS= read -r l; do
        [ -n "$l" ] || continue
        loc="${l%%:*}"; rest="${l#*:}"; line="${rest%%:*}"
        detail "$(printf '%-45s %s' "${loc#"$BASE"/}:$line" "$(printf '%s' "${rest#*:}" | sed 's/^[[:space:]]*//' | cut -c1-60)")"
    done <<< "$calls11"
    detail "they were retired in Fase 11: point it at Sumi Shell, or roll it"
    detail "back per Quickshell/docs/MIGRATION.md §Fase 11"
fi

# Fase 4: `swaync-client` (su CLI, el que colgaba matugen contra una unidad
# enmascarada), su unidad, o una ruta dentro de swaync/. El binario ya no existe,
# así que una llamada viva no falla silenciosa: falla y punto.
calls4=""
if [ "${#ref_dirs[@]}" -gt 0 ]; then
    calls4="$(grep -rInE '[/"'"'"'$~]swaync/[A-Za-z0-9_./-]+|swaync-client|swaync\.service|(systemctl|pkill|pgrep)[^;&|]*\bswaync\b' \
                 "${ref_dirs[@]}" --exclude='*.md' --exclude='*.txt' --exclude-dir=.git \
                 --exclude='check-config-drift.sh' 2>/dev/null \
               | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|--|//|/?\*)' || true)"
fi
if [ -n "$calls4" ]; then
    warn "retired pieces — something live still calls SwayNC"
    while IFS= read -r l; do
        [ -n "$l" ] || continue
        loc="${l%%:*}"; rest="${l#*:}"; line="${rest%%:*}"
        detail "$(printf '%-45s %s' "${loc#"$BASE"/}:$line" "$(printf '%s' "${rest#*:}" | sed 's/^[[:space:]]*//' | cut -c1-60)")"
    done <<< "$calls4"
    detail "SwayNC was retired and uninstalled in Fase 4: the shell serves"
    detail "notifications (Quickshell/docs/FASE9/NOTIFICACIONES.md §14)"
fi

if [ -n "$calls" ]; then
    warn "retired rofi menus — something live still calls one"
    while IFS= read -r l; do
        [ -n "$l" ] || continue
        loc="${l%%:*}"; rest="${l#*:}"; line="${rest%%:*}"
        what="$(grep -oE "rofi/($alt)" <<< "$rest" | head -1)"
        detail "$(printf '%-45s %s' "${loc#"$BASE"/}:$line" "$what")"
    done <<< "$calls"
    detail "the menu is gone: point it at the shell's surface (sumi:<name>),"
    detail "or roll it back per Quickshell/docs/MIGRATION.md §Sub-fase 10.e"
fi

exit "$problems"
