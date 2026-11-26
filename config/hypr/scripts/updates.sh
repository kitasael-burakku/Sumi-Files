#!/usr/bin/env bash
# ============================================================================
#  updates.sh — update checker (pacman + AUR)
# ----------------------------------------------------------------------------
#  Escrito para el modulo `custom/updates` de Waybar, que se retiro en la
#  Fase 11 (2026-09-21). Sigue vivo porque su JSON en cache es lo que lee
#  Sumi Shell (`services/Updates.qml`), lo que refresca `updates-check.timer`
#  cada 30 min y lo que resume `updates-notify-actionable.sh`. Por eso se mudo
#  de `waybar/scripts/` a `hypr/scripts/`, con el resto de la tuberia del rice.
#
#  Modes:
#    (no args)   JSON, served from cache when it's still fresh
#    --force     refresh the cache first, then print the JSON
#                (this is what updates-check.service calls every 30 min)
#    --list      human-readable list of what would be updated (right click)
#    --plain     one-line plain-text summary, for notifications
#
#  The package list is cached alongside the JSON so --list is instant and
#  never re-runs the network check just to show what was already counted.
# ============================================================================
set -o pipefail

CACHE_FILE="${XDG_RUNTIME_DIR:-/tmp}/sumi-updates.cache"
PKGS_FILE="${XDG_RUNTIME_DIR:-/tmp}/sumi-updates.pkgs"
NOTIFIED_FILE="${XDG_RUNTIME_DIR:-/tmp}/sumi-updates.notified"
FAILED_FILE="${XDG_RUNTIME_DIR:-/tmp}/sumi-updates.failed"
PLAIN_FILE="${XDG_RUNTIME_DIR:-/tmp}/sumi-updates.plain"
CACHE_TTL=300   # 5 minutes
FEW=12          # at most this many packages get listed inside the tooltip
MANY=50         # from here on the module goes "critical"

mode="${1:-}"

# ── Escaping ────────────────────────────────────────────────────────────────
# Two different jobs: JSON is the transport, Pango is what the tooltip is
# marked up with (heredado del módulo de Waybar; el formato sigue siendo el
# contrato de la caché). A package name is never going to contain "<", but versions
# come from a network source and the whole widget breaks silently if one ever
# does, so both are applied.
# JSON no admite NINGÚN carácter de control sin escapar (U+0000–U+001F). Antes
# sólo se escapaba el salto de línea y el error de yay sin red trae un tabulador
# («\t* request failed…»): la caché quedaba inválida y el shell decía «cache
# ilegible» (visto el 2026-09-15). Tab y CR se escapan; el resto (p. ej. el ESC
# de los colores ANSI) se elimina.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    s="$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')"
    printf '%s' "$s"
}

pango_escape() {
    local s="$1"
    # The backslashes are load-bearing: since bash 5.2 an unescaped & in the
    # replacement of ${var//pat/repl} expands to the matched text, so "&lt;"
    # silently produced "<lt;" instead of an entity.
    s="${s//&/\&amp;}"
    s="${s//</\&lt;}"
    s="${s//>/\&gt;}"
    printf '%s' "$s"
}

# stderr de una herramienta → una línea legible para el tooltip: sin colores ANSI,
# sin CR, tabuladores y saltos de línea como espacios.
one_line() {
    sed 's/\x1b\[[0-9;]*[A-Za-z]//g' "$1" | tr '\n\t\r' '   ' | sed 's/  */ /g; s/^ *//; s/ *$//'
}

# ── Kernel detection ────────────────────────────────────────────────────────
# A kernel update means the running system loses its modules until reboot, so
# it's worth calling out. Matched by name because the package isn't installed
# yet (sysupdate.fish can use the /usr/lib/modules trick precisely because
# there it already happened). Excludes the linux-* packages that aren't
# kernels: linux-firmware*, linux-api-headers, *-headers, docs, tools.
is_kernel_pkg() {
    local n="$1"
    [[ "$n" == linux || "$n" == linux-* ]] || return 1
    [[ "$n" == *headers* || "$n" == *firmware* || "$n" == *api* \
       || "$n" == *docs* || "$n" == *tools* ]] && return 1
    return 0
}

# ── The actual check ────────────────────────────────────────────────────────
# Fills: updates, aur, aur_helper, error_msg — and writes PKGS_FILE as TSV
# (source, name, old version, new version).
run_check() {
    updates=0
    aur=0
    error_msg=""
    local tmp_pkgs
    tmp_pkgs="$(mktemp "${PKGS_FILE}.XXXXXX")"

    # pacman (pacman-contrib's checkupdates doesn't touch the real database)
    # checkupdates documents its exit codes: 0 = updates available, 2 = no
    # updates (normal case, not a failure), anything else (e.g. 1: couldn't
    # sync the temp DB — no network, lock, etc.) is a real failure.
    if command -v checkupdates >/dev/null 2>&1; then
        local cu_out cu_err cu_rc
        cu_out="$(mktemp)"; cu_err="$(mktemp)"
        checkupdates >"$cu_out" 2>"$cu_err"
        cu_rc=$?
        updates=$(grep -c '[^[:space:]]' "$cu_out")
        if (( cu_rc != 0 && cu_rc != 2 )); then
            error_msg="checkupdates: $(one_line "$cu_err")"
        fi
        awk 'NF>=4 {print "pacman\t"$1"\t"$2"\t"$4}' "$cu_out" >>"$tmp_pkgs"
        rm -f "$cu_out" "$cu_err"
    else
        error_msg="checkupdates not found (install pacman-contrib)"
    fi

    # AUR — supports yay or paru automatically
    aur_helper=""
    if command -v yay >/dev/null 2>&1; then
        aur_helper="yay"
    elif command -v paru >/dev/null 2>&1; then
        aur_helper="paru"
    fi

    if [[ -n "$aur_helper" ]]; then
        # Unlike checkupdates, yay/paru -Qua exits with code 1 both in the
        # normal "no AUR updates" case and on a real failure, and there's no
        # way to tell them apart from the exit code alone. A real failure (no
        # network, RPC down, etc.) does print something to stderr; "no
        # updates" prints nothing. timeout killing the process (124) also
        # counts as a failure.
        local au_out au_err au_rc
        au_out="$(mktemp)"; au_err="$(mktemp)"
        timeout 20 "$aur_helper" -Qua >"$au_out" 2>"$au_err"
        au_rc=$?
        # One retry: the AUR RPC resets connections now and then (seen
        # 2026-11-25, "connection reset by peer"), and a single blip used to
        # flag the whole check as failed and fire a critical notification.
        if (( au_rc == 124 )) || { (( au_rc != 0 )) && [[ -s "$au_err" ]]; }; then
            sleep 3
            timeout 20 "$aur_helper" -Qua >"$au_out" 2>"$au_err"
            au_rc=$?
        fi
        aur=$(grep -c '[^[:space:]]' "$au_out")
        if (( au_rc == 124 )); then
            error_msg="${error_msg:+$error_msg; }$aur_helper: timeout (20s)"
        elif (( au_rc != 0 )) && [[ -s "$au_err" ]]; then
            error_msg="${error_msg:+$error_msg; }$aur_helper: $(one_line "$au_err")"
        fi
        awk 'NF>=4 {print "aur\t"$1"\t"$2"\t"$4}' "$au_out" >>"$tmp_pkgs"
        rm -f "$au_out" "$au_err"
    fi

    # Sanitize (in case grep returns empty or timeout kills the process)
    [[ "$updates" =~ ^[0-9]+$ ]] || updates=0
    [[ "$aur"     =~ ^[0-9]+$ ]] || aur=0

    # Written atomically, same as the JSON cache: --list may be reading it
    mv -f "$tmp_pkgs" "$PKGS_FILE"
}

# ── Aligned "name  old → new" block, one line per package ──────────────────
# Takes the source filter as $1 ("pacman", "aur" or "" for all).
format_pkgs() {
    local want="$1"
    [[ -f "$PKGS_FILE" ]] || return 0
    awk -F'\t' -v want="$want" '
        want == "" || $1 == want {
            n[++c] = $2; o[c] = $3; v[c] = $4
            if (length($2) > wn) wn = length($2)
            if (length($3) > wo) wo = length($3)
        }
        END { for (i = 1; i <= c; i++) printf "%-*s  %*s → %s\n", wn, n[i], wo, o[i], v[i] }
    ' "$PKGS_FILE"
}

kernel_pkgs() {
    [[ -f "$PKGS_FILE" ]] || return 0
    local name
    # Only field 2 matters here; the rest are placeholders so the tab-split
    # lands `name` in the right column.
    while IFS=$'\t' read -r _ name _ _; do
        is_kernel_pkg "$name" && printf '%s\n' "$name"
    done < "$PKGS_FILE"
}

# ── --list: the readable window behind the right click ──────────────────────
if [[ "$mode" == "--list" ]]; then
    # Only re-check if there's nothing cached at all; otherwise this must be
    # instant. The bar and this list then always agree on what they show.
    if [[ ! -f "$PKGS_FILE" ]]; then
        printf 'Checking for updates...\n' >&2
        run_check
    fi

    pac=$(awk -F'\t' '$1=="pacman"' "$PKGS_FILE" 2>/dev/null | grep -c '[^[:space:]]')
    au=$(awk -F'\t' '$1=="aur"' "$PKGS_FILE" 2>/dev/null | grep -c '[^[:space:]]')
    tot=$((pac + au))

    {
        if (( tot == 0 )); then
            printf '\n  System up to date — nothing to update.\n\n'
        else
            printf '\n  Pending updates — %d total (%d pacman, %d AUR)\n' "$tot" "$pac" "$au"
            if (( pac > 0 )); then
                printf '\n  PACMAN (%d)\n\n' "$pac"
                format_pkgs pacman | sed 's/^/    /'
            fi
            if (( au > 0 )); then
                printf '\n  AUR (%d)\n\n' "$au"
                format_pkgs aur | sed 's/^/    /'
            fi
            mapfile -t kern < <(kernel_pkgs)
            if (( ${#kern[@]} > 0 )); then
                printf '\n  Kernel update included (%s) — reboot after updating.\n' \
                    "$(IFS=', '; printf '%s' "${kern[*]}")"
            fi
            printf '\n  Run sysupdate (or left click the module) to apply.\n\n'
        fi
        printf '  Cache written: %s\n\n' \
            "$([[ -f "$PKGS_FILE" ]] && date -r "$PKGS_FILE" '+%Y-%m-%d %H:%M' || echo 'never')"
    } | if [[ -t 1 ]] && command -v less >/dev/null 2>&1; then
            less -R -X
        else
            cat
        fi
    exit 0
fi

# ── Serve from cache unless forced ──────────────────────────────────────────
if [[ "$mode" != "--force" && -f "$CACHE_FILE" ]]; then
    age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") ))
    if (( age < CACHE_TTL )); then
        if [[ "$mode" == "--plain" ]]; then
            # Written next to the JSON by the same run, so this never has to
            # re-derive the summary by parsing the widget's own output back.
            [[ -f "$PLAIN_FILE" ]] && { cat "$PLAIN_FILE"; exit 0; }
        else
            cat "$CACHE_FILE"
            exit 0
        fi
    fi
fi

run_check
total=$((updates + aur))
mapfile -t kern < <(kernel_pkgs)

# ── Build output ────────────────────────────────────────────────────────────
if (( total == 0 )); then
    text="󰄬"
    tooltip="System up to date"$'\n'"Last checked $(date '+%H:%M')"
    css_class="updated"
    plain="System up to date"
else
    text="󰚰 $total"
    if (( total >= MANY )); then css_class="critical"; else css_class="pending"; fi

    counts="$updates pacman"
    [[ -n "$aur_helper" ]] && counts="$counts · $aur AUR ($aur_helper)"
    plain="$total update$( (( total != 1 )) && printf s ) available — $counts"

    tooltip="$total update$( (( total != 1 )) && printf s ) available"$'\n'"$counts"

    if (( total <= FEW )); then
        # Few enough to read at a glance: show them right here, monospaced so
        # the version columns line up.
        tooltip="$tooltip"$'\n\n'"<tt>$(pango_escape "$(format_pkgs '')")</tt>"
    fi

    if (( ${#kern[@]} > 0 )); then
        tooltip="$tooltip"$'\n\n'"⚠ Kernel update ($(IFS=', '; printf '%s' "${kern[*]}")) — reboot after updating"
    fi

    if (( total > FEW )); then
        tooltip="$tooltip"$'\n\n'"Right click to view the packages that would be updated"
    fi
    tooltip="$tooltip"$'\n'"Left click to update · Middle click to re-check"
fi

classes=("$css_class")

# ── Risk check ──────────────────────────────────────────────────────────────
# `sysupdate check` knows when an update would leave a package running against
# dependencies it was not rebuilt for (quickshell vs a new Qt). checkupdates
# just synced its database, so --no-sync costs no network; --no-aur because
# the AUR side has no such check. Optional: without sysupdate, nothing changes.
# Besides the text, the cache gets the package names and the globs sysupdate
# suggests holding back as JSON arrays (risk_packages, risk_ignore), so Sumi
# Shell does not have to parse them out of the sentence.
risk="" risk_packages="[]" risk_ignore="[]"
if (( updates > 0 )) && command -v sysupdate >/dev/null 2>&1; then
    mapfile -t risk_lines < <(timeout 60 sysupdate check --json --no-sync --no-aur 2>/dev/null | python3 -I -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit()
if d.get("risky"):
    pkgs = [str(r["package"]) for r in d.get("risks", []) if isinstance(r, dict) and r.get("package")]
    ignore = [str(g) for g in d.get("suggested_ignore") or []]
    tip = (", ".join(pkgs) or "some packages") + " would run against dependencies it was not rebuilt for"
    if ignore:
        tip += " — safe: sysupdate -i \x27" + ",".join(ignore) + "\x27"
    print(" ".join(tip.split()))
    print(json.dumps(pkgs, separators=(",", ":")))
    print(json.dumps(ignore, separators=(",", ":")))
' 2>/dev/null)
    if (( ${#risk_lines[@]} == 3 )); then
        risk="${risk_lines[0]}" risk_packages="${risk_lines[1]}" risk_ignore="${risk_lines[2]}"
    fi
fi
if [[ -n "$risk" ]]; then
    tooltip="$tooltip"$'\n\n'"⚠ Risky: $(pango_escape "$risk")"
    plain="$plain — risky: $risk"
fi

if [[ -n "$error_msg" ]]; then
    text="$text 󰀦 " 
    tooltip="$tooltip"$'\n\n'"⚠ $(pango_escape "$error_msg")"
    plain="$plain (check failed: $error_msg)"
    classes+=("error")
fi

printf '%s\n' "$plain" > "$PLAIN_FILE"

if [[ "$mode" == "--plain" ]]; then
    printf '%s\n' "$plain"
    exit 0
fi

# ── Desktop notification ────────────────────────────────────────────────────
# `-a` era "Waybar" desde que esto era su módulo. Ya no es cosmético: desde
# la Fase 4 (2026-09-22) el servidor de notificaciones es el shell, y su
# NotifCard imprime el app name tal cual — las tarjetas decían «Waybar», un
# programa desinstalado en la Fase 11. Ahora es "minimaru", el mismo que ya
# usaba updates-notify-actionable.sh, así que las dos agrupan juntas.
# Only alerts when the total rises above the last alert (not on every
# cache refresh), and resets to 0 as soon as the system is up to date so
# the next batch of updates triggers a notification again.
last_notified=0
[[ -f "$NOTIFIED_FILE" ]] && last_notified=$(<"$NOTIFIED_FILE")
[[ "$last_notified" =~ ^[0-9]+$ ]] || last_notified=0

if (( total > 0 && total > last_notified )) && command -v notify-send >/dev/null 2>&1; then
    body="$updates pacman$( [[ -n "$aur_helper" ]] && printf ' · %s AUR (%s)' "$aur" "$aur_helper" )"
    (( ${#kern[@]} > 0 )) && body="$body"$'\n'"Kernel update included — reboot after updating"
    [[ -n "$risk" ]] && body="$body"$'\n'"⚠ Risky: $risk"
    notify-send -a "minimaru" -i software-update-available \
        "󰚰 Updates available" "$body"
fi
printf '%s\n' "$total" > "$NOTIFIED_FILE"

# Same as above but for failures: only alerts when entering a failed state
# (not on every refresh while it keeps failing) and resets as soon as it
# works again.
was_failed=0
[[ -f "$FAILED_FILE" ]] && was_failed=$(<"$FAILED_FILE")
[[ "$was_failed" =~ ^(0|1)$ ]] || was_failed=0

if [[ -n "$error_msg" ]]; then
    if (( was_failed == 0 )) && command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical -a "minimaru" -i dialog-warning \
            "󰀦  Failed to check for updates" "$error_msg"
    fi
    printf '1\n' > "$FAILED_FILE"
else
    printf '0\n' > "$FAILED_FILE"
fi

class_json=$(printf '"%s",' "${classes[@]}")
class_json="[${class_json%,}]"

result="{\"text\":\"$(json_escape "$text")\",\"tooltip\":\"$(json_escape "$tooltip")\",\"class\":${class_json},\"risk\":\"$(json_escape "$risk")\",\"risk_packages\":${risk_packages},\"risk_ignore\":${risk_ignore}}"

# Write the cache atomically (el FileView del shell la vigila con watch:
# evita que lea un archivo a medio escribir)
tmp="$(mktemp "${CACHE_FILE}.XXXXXX")"
printf '%s\n' "$result" > "$tmp"
mv -f "$tmp" "$CACHE_FILE"

printf '%s\n' "$result"
