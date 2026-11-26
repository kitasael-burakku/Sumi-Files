#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# ============================================================================
#  install.sh — optional installer for Sumi-Files: copies (or links) the
#  files listed in sumi-files.list from config/ into ~/.config.
# ----------------------------------------------------------------------------
#  Non-destructive by design: every file it would replace is first MOVED to a
#  timestamped backup folder, never overwritten in place. It never uses sudo,
#  never installs packages and never deletes anything in ~/.config.
#  Installing by hand is just as supported: docs/INSTALLATION.md.
# ============================================================================
set -u
set -o pipefail

VERSION="0.1.0"
PROG="install.sh"

E_OK=0 E_FAIL=1 E_USAGE=64 E_DATA=65 E_NOINPUT=66 E_UNAVAILABLE=69
E_CANTCREAT=73 E_NOPERM=77 E_CANCEL=130

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PAYLOAD="$REPO/config"
MANIFEST="$REPO/sumi-files.list"
TARGET="${XDG_CONFIG_HOME:-$HOME/.config}"
DEFAULT_TARGET="$TARGET"
BIN_DIR="$HOME/.local/bin"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sumi-files/backups/$STAMP"

DRY_RUN=0 YES=0 LINK=0 NO_BACKUP=0 FORCE=0 WITH_TOOLS=0 ENABLE_SERVICES=0
SKIP_COLORS=0 QUIET=0 COLOR=0
ONLY=()

# ── Output ──────────────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then COLOR=1; fi
c() { [ "$COLOR" = 1 ] && printf '\033[%sm' "$1"; }
say()  { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
note() { [ "$QUIET" = 1 ] || printf '%s  %s%s\n' "$(c 90)" "$*" "$(c 0)"; }
ok()   { [ "$QUIET" = 1 ] || printf '%s  ✓ %s%s\n' "$(c 32)" "$*" "$(c 0)"; }
warn() { printf '%s  ⚠ %s%s\n' "$(c 33)" "$*" "$(c 0)" >&2; }
err()  { printf '%s  ✘ %s%s\n' "$(c 31)" "$*" "$(c 0)" >&2; }
die()  { local code="$1"; shift; err "$*"; exit "$code"; }
usage_error() { printf '%s: %s\nTry '\''%s --help'\''.\n' "$PROG" "$*" "$PROG" >&2; exit "$E_USAGE"; }

usage() {
    cat <<EOF
Usage: ./install.sh [OPTIONS]

Copy (or link) the Sumi-Files configuration into ~/.config. Files that would
be replaced are moved to a backup folder first. Nothing is deleted.

Options:
  -t, --target DIR       install into DIR instead of ${DEFAULT_TARGET/#$HOME/\~}
  -o, --only PATH        only this manifest entry (e.g. kitty or hypr/modules), repeatable
  -l, --link             symlink files instead of copying them (files with @HOME@
                         placeholders are always copied)
  -n, --dry-run          show what would happen; change nothing
  -y, --yes              don't ask for confirmation
  -b, --backup-dir DIR   where replaced files go
                         (default: ~/.local/state/sumi-files/backups/<date>)
      --no-backup        replace files without keeping a copy (requires --force)
      --force            allow --no-backup
      --with-tools       also install dotbackup, diskbackup and sysupdate into ~/.local/bin
      --bin-dir DIR      where --with-tools installs (default: ~/.local/bin)
      --enable-services  enable the systemd --user units after installing
      --skip-colors      don't run apply-static-colors.sh afterwards
  -q, --quiet            less output
      --no-color         plain output (also honoured: NO_COLOR)
  -h, --help             this help
  -V, --version          print the version

Exit codes: 0 ok · 1 failed · 64 usage · 65 bad data · 66 missing path
            69 missing dependency · 73 can't create · 77 permission denied · 130 cancelled
EOF
}

# ── Arguments ───────────────────────────────────────────────────────────────
need_value() { [ $# -ge 2 ] && [ -n "$2" ] || usage_error "$1 needs a value"; }
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit "$E_OK" ;;
        -V|--version) echo "$PROG $VERSION"; exit "$E_OK" ;;
        -t|--target) need_value "$@"; TARGET="$2"; shift ;;
        --target=*) TARGET="${1#*=}" ;;
        -o|--only) need_value "$@"; ONLY+=("${2%/}"); shift ;;
        --only=*) ONLY+=("${1#*=}") ;;
        -l|--link) LINK=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        -y|--yes) YES=1 ;;
        -b|--backup-dir) need_value "$@"; BACKUP_DIR="$2"; shift ;;
        --backup-dir=*) BACKUP_DIR="${1#*=}" ;;
        --no-backup) NO_BACKUP=1 ;;
        --force) FORCE=1 ;;
        --with-tools) WITH_TOOLS=1 ;;
        --bin-dir) need_value "$@"; BIN_DIR="$2"; shift ;;
        --bin-dir=*) BIN_DIR="${1#*=}" ;;
        --enable-services) ENABLE_SERVICES=1 ;;
        --skip-colors) SKIP_COLORS=1 ;;
        -q|--quiet) QUIET=1 ;;
        --no-color) COLOR=0 ;;
        --) shift; break ;;
        -*) usage_error "unknown option '$1'" ;;
        *) usage_error "unexpected argument '$1'" ;;
    esac
    shift
done
[ $# -eq 0 ] || usage_error "unexpected argument '$1'"
[ "$NO_BACKUP" = 1 ] && [ "$FORCE" != 1 ] && usage_error "--no-backup replaces files without a copy; add --force if you mean it"
if [ "$DRY_RUN" = 0 ] && [ "$YES" = 0 ] && [ ! -t 0 ]; then
    usage_error "stdin is not a terminal: pass --yes (or --dry-run)"
fi

abs() { # absolute path without requiring it to exist
    case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$PWD" "$1" ;; esac
}
TARGET="$(abs "${TARGET/#\~/$HOME}")"
BACKUP_DIR="$(abs "${BACKUP_DIR/#\~/$HOME}")"
BIN_DIR="$(abs "${BIN_DIR/#\~/$HOME}")"

# ── Validation ──────────────────────────────────────────────────────────────
for cmd in cp mv ln mkdir sed cmp find dirname realpath; do
    command -v "$cmd" >/dev/null 2>&1 || die "$E_UNAVAILABLE" "missing dependency: $cmd"
done
[ -f "$MANIFEST" ] || die "$E_NOINPUT" "manifest not found: $MANIFEST"
[ -d "$PAYLOAD" ] || die "$E_NOINPUT" "payload not found: $PAYLOAD"
case "$(realpath -m -- "$TARGET")/" in "$REPO/"*) die "$E_DATA" "the target can't be inside the repository" ;; esac
case "$BACKUP_DIR/" in "$TARGET/"*|"$REPO/"*) die "$E_DATA" "the backup folder must be outside the target and the repository" ;; esac
if [ -e "$TARGET" ] && [ ! -d "$TARGET" ]; then die "$E_DATA" "$TARGET exists and is not a directory"; fi
if [ -d "$TARGET" ] && [ ! -w "$TARGET" ]; then die "$E_NOPERM" "can't write to $TARGET"; fi

# Files the repository actually ships. In a git checkout that is what git
# tracks, so private or generated files sitting in a working tree (a
# dotbackup mirror, for instance) are never installed on another machine.
declare -A SHIPPED=()
if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    while IFS= read -r -d '' f; do
        # tracked but deleted in this working tree: nothing to install
        [ -e "$REPO/$f" ] || [ -L "$REPO/$f" ] || continue
        SHIPPED["${f#config/}"]=1
    done < <(git -C "$REPO" ls-files -z -- config)
    # plus files not committed yet but not ignored either (a fresh clone of a
    # fork, local additions); ignored files — private, generated — never ship
    while IFS= read -r -d '' f; do SHIPPED["${f#config/}"]=1; done \
        < <(git -C "$REPO" ls-files -z --others --exclude-standard -- config)
else
    while IFS= read -r -d '' f; do f="${f#"$PAYLOAD"/}"; SHIPPED["$f"]=1; done \
        < <(find "$PAYLOAD" \( -type f -o -type l \) -print0)
fi

# ── Manifest → list of (repo file, installed path) ─────────────────────────
safe_rel() { # relative, never climbing out
    case "$1" in ''|/*|.|./) return 1 ;; esac
    case "/$1/" in */../*) return 1 ;; esac
    return 0
}
selected() {
    [ "${#ONLY[@]}" -eq 0 ] && return 0
    local o
    for o in "${ONLY[@]}"; do
        case "$1/" in "$o/"*) return 0 ;; esac
        case "$o/" in "$1/"*) return 0 ;; esac
    done
    return 1
}

SRC_FILES=() DST_FILES=()
n=0 bad=0
while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="$(printf '%s' "$line" | sed -E 's/(^|[[:space:]])#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$line" ] || continue
    src="$line" dst="$line"
    case "$line" in *"=>"*)
        src="$(printf '%s' "${line%%=>*}" | sed -E 's/[[:space:]]+$//')"
        dst="$(printf '%s' "${line#*=>}" | sed -E 's/^[[:space:]]+//')" ;;
    esac
    base="$TARGET" rel="$src"
    # shellcheck disable=SC2088 # a literal "~/" in the manifest, not an expansion
    case "$src" in "~/"*) base="$HOME" rel="${src#\~/}" ;; esac
    rel="${rel%/}" dstrel="${dst#\~/}"; dstrel="${dstrel%/}"
    if ! safe_rel "$rel" || ! safe_rel "$dstrel"; then
        err "$MANIFEST:$n: invalid entry '$line'"; bad=1; continue
    fi
    selected "$dstrel" || continue
    if [ -d "$PAYLOAD/$dstrel" ]; then
        for f in "${!SHIPPED[@]}"; do
            case "$f" in "$dstrel"/*)
                SRC_FILES+=("$f"); DST_FILES+=("$base/$rel/${f#"$dstrel"/}") ;;
            esac
        done
    elif [ -n "${SHIPPED[$dstrel]:-}" ]; then
        SRC_FILES+=("$dstrel"); DST_FILES+=("$base/$rel")
    fi
done < "$MANIFEST"
[ "$bad" = 0 ] || exit "$E_DATA"
[ "${#SRC_FILES[@]}" -gt 0 ] || die "$E_DATA" "nothing to install${ONLY[*]:+ for: ${ONLY[*]}}"

# Stable order for the report
mapfile -t ORDER < <(for i in "${!SRC_FILES[@]}"; do printf '%s\t%s\n' "${SRC_FILES[$i]}" "$i"; done | sort | cut -f2)

# ── Placeholders ────────────────────────────────────────────────────────────
# The repository stores @HOME@ where a config needs an absolute home path
# (qt5ct/qt6ct can't expand ~). Those files are always copied, rendered.
home_sed="$(printf '%s' "$HOME" | sed -e 's/[\\&|]/\\&/g')"
templated() { grep -qF '@HOME@' -- "$1" 2>/dev/null; }
render() { sed "s|@HOME@|$home_sed|g" -- "$1"; }

same_content() { # repo file, installed path
    local s="$PAYLOAD/$1" d="$2"
    if [ "$LINK" = 1 ] && ! templated "$s"; then
        [ -L "$d" ] && [ "$(readlink -- "$d")" = "$s" ]
        return
    fi
    [ -f "$d" ] && [ ! -L "$d" ] || return 1
    if templated "$s"; then cmp -s <(render "$s") "$d"; else cmp -s -- "$s" "$d"; fi
}

# ── Plan ────────────────────────────────────────────────────────────────────
ACTIONS=()
new=0 replace=0 same=0
for i in "${ORDER[@]}"; do
    s="${SRC_FILES[$i]}" d="${DST_FILES[$i]}"
    if [ -e "$d" ] || [ -L "$d" ]; then
        if same_content "$s" "$d"; then ACTIONS[i]="="; same=$((same + 1))
        elif case "$(realpath -m -- "$d")/" in "$REPO/"*) true ;; *) false ;; esac; then
            # ~/.config already points into this repository (a symlinked
            # folder, an earlier --link): replacing it would move the
            # repository's own file away and link it to itself.
            ACTIONS[i]="="; same=$((same + 1))
            warn "${d/#$HOME/\~} already resolves into the repository; left alone"
        else ACTIONS[i]="~"; replace=$((replace + 1)); fi
    else
        ACTIONS[i]="+"; new=$((new + 1))
    fi
done

say ""
say "$(c 1)  Sumi-Files $VERSION → $TARGET$(c 0)"
[ "$LINK" = 1 ] && note "mode: symlinks into $REPO"
for i in "${ORDER[@]}"; do
    a="${ACTIONS[$i]}" d="${DST_FILES[$i]/#$HOME/\~}"
    case "$a" in
        +) [ "$QUIET" = 1 ] || printf '%s    + %s%s\n' "$(c 32)" "$d" "$(c 0)" ;;
        "~") [ "$QUIET" = 1 ] || printf '%s    ~ %s%s\n' "$(c 33)" "$d" "$(c 0)" ;;
    esac
done
say ""
say "  $new new · $replace replaced · $same already installed"
if [ "$replace" -gt 0 ]; then
    if [ "$NO_BACKUP" = 1 ]; then warn "--no-backup: the $replace replaced file(s) will NOT be kept"
    else note "replaced files are moved to ${BACKUP_DIR/#$HOME/\~}"; fi
fi

if [ "$DRY_RUN" = 1 ]; then
    [ "$WITH_TOOLS" = 1 ] && note "would install dotbackup, diskbackup and sysupdate into ${BIN_DIR/#$HOME/\~}"
    [ "$ENABLE_SERVICES" = 1 ] && note "would enable the systemd --user units"
    say ""; note "dry run: nothing was changed"; exit "$E_OK"
fi

confirm() {
    [ "$YES" = 1 ] && return 0
    printf '%s  %s [y/N] %s' "$(c 1)" "$1" "$(c 0)" >&2
    local reply
    read -r reply || { echo >&2; exit "$E_CANCEL"; }
    case "$reply" in y|Y|yes|YES) return 0 ;; esac
    return 1
}

if [ $((new + replace)) -gt 0 ] || [ "$WITH_TOOLS" = 1 ] || [ "$ENABLE_SERVICES" = 1 ]; then
    confirm "Install?" || { say "  cancelled: nothing was changed"; exit "$E_OK"; }
fi
trap 'echo >&2; err "interrupted — already-replaced files are in $BACKUP_DIR"; exit $E_CANCEL' INT TERM

# ── Install ─────────────────────────────────────────────────────────────────
backup_one() { # installed path → moved under BACKUP_DIR, same tree
    local d="$1" rel
    case "$d" in "$TARGET"/*) rel="config/${d#"$TARGET"/}" ;; "$HOME"/*) rel="home/${d#"$HOME"/}" ;; *) rel="other${d}" ;; esac
    # replaced configs may be private: the backup folder is owner-only
    (umask 077 && mkdir -p -- "$BACKUP_DIR/$(dirname -- "$rel")") || die "$E_CANTCREAT" "can't create $BACKUP_DIR"
    mv -- "$d" "$BACKUP_DIR/$rel" || die "$E_FAIL" "can't move $d to the backup"
}

installed=0
for i in "${ORDER[@]}"; do
    a="${ACTIONS[$i]}"
    [ "$a" = "=" ] && continue
    s="$PAYLOAD/${SRC_FILES[$i]}" d="${DST_FILES[$i]}"
    parent="$(dirname -- "$d")"
    if [ -e "$parent" ] && [ ! -d "$parent" ]; then
        die "$E_DATA" "$parent exists and is not a directory"
    fi
    mkdir -p -- "$parent" 2>/dev/null || die "$E_CANTCREAT" "can't create $parent"
    [ -w "$parent" ] || die "$E_NOPERM" "can't write to $parent"
    if [ "$a" = "~" ]; then
        if [ "$NO_BACKUP" = 1 ]; then rm -f -- "$d"; else backup_one "$d"; fi
    fi
    if templated "$s"; then
        render "$s" > "$d" || die "$E_FAIL" "can't write $d"
        chmod --reference="$s" -- "$d" 2>/dev/null || true
    elif [ "$LINK" = 1 ]; then
        ln -s -- "$s" "$d" || die "$E_FAIL" "can't link $d"
    else
        cp -P -p -- "$s" "$d" || die "$E_FAIL" "can't copy $d"
    fi
    installed=$((installed + 1))
done
ok "$installed file(s) installed"
[ -d "$BACKUP_DIR" ] && note "previous versions: $BACKUP_DIR"

# ── Tools ───────────────────────────────────────────────────────────────────
if [ "$WITH_TOOLS" = 1 ]; then
    mkdir -p -- "$BIN_DIR" || die "$E_CANTCREAT" "can't create $BIN_DIR"
    for tool in dotbackup diskbackup sysupdate; do
        d="$BIN_DIR/$tool"
        if [ -e "$d" ] || [ -L "$d" ]; then
            if [ -L "$d" ] && [ "$(readlink -- "$d")" = "$REPO/bin/$tool" ]; then continue; fi
            if [ "$NO_BACKUP" = 1 ]; then
                rm -f -- "$d"
            elif ! { (umask 077 && mkdir -p -- "$BACKUP_DIR/bin") && mv -- "$d" "$BACKUP_DIR/bin/$tool"; }; then
                die "$E_FAIL" "can't back up $d"
            fi
        fi
        if [ "$LINK" = 1 ]; then ln -s -- "$REPO/bin/$tool" "$d"; else cp -p -- "$REPO/bin/$tool" "$d"; fi \
            || die "$E_FAIL" "can't install $d"
    done
    ok "dotbackup, diskbackup and sysupdate installed in ${BIN_DIR/#$HOME/\~}"
    # A copied dotbackup can't find the repository by its own location.
    conf="${XDG_CONFIG_HOME:-$HOME/.config}/sumi-files/dotbackup.conf"
    if [ "$LINK" = 0 ] && [ ! -e "$conf" ]; then
        mkdir -p -- "$(dirname -- "$conf")" && printf 'repo = %s\n' "$REPO" > "$conf" \
            && note "wrote $conf (repo = $REPO)"
    fi
    case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "$BIN_DIR is not in \$PATH" ;; esac
fi

# ── Colours and services ────────────────────────────────────────────────────
if [ "$SKIP_COLORS" = 0 ]; then
    if [ "$TARGET" = "$HOME/.config" ] && [ -x "$TARGET/hypr/scripts/apply-static-colors.sh" ]; then
        if "$TARGET/hypr/scripts/apply-static-colors.sh" >/dev/null 2>&1; then
            ok "static palette applied"
        else
            warn "apply-static-colors.sh reported an error"
        fi
    else
        note "run hypr/scripts/apply-static-colors.sh from the installed tree before the first session"
    fi
fi

if [ "$ENABLE_SERVICES" = 1 ]; then
    command -v systemctl >/dev/null 2>&1 || die "$E_UNAVAILABLE" "systemctl not found"
    units=()
    for f in "$TARGET"/systemd/user/*.service "$TARGET"/systemd/user/*.timer; do
        [ -f "$f" ] || continue
        grep -q '^\[Install\]' "$f" || continue
        u="$(basename -- "$f")"
        # a timer's service is started by the timer, not enabled on its own
        case "$u" in *.service) [ -f "${f%.service}.timer" ] && continue ;; esac
        # polkit-agent.service is the fallback: Sumi Shell carries its own agent
        [ "$u" = polkit-agent.service ] && continue
        # the reminder needs dotbackup on $PATH
        if [ "$u" = dotbackup-remind.timer ] && ! command -v dotbackup >/dev/null 2>&1 \
            && [ ! -x "$BIN_DIR/dotbackup" ]; then continue; fi
        units+=("$u")
    done
    if [ "${#units[@]}" -gt 0 ]; then
        if systemctl --user daemon-reload && systemctl --user enable -- "${units[@]}"; then
            ok "enabled: ${units[*]}"
        else
            warn "systemctl --user enable failed"
        fi
    fi
fi

say ""
say "  Next: docs/INSTALLATION.md § After installing (personal values, plugins, first login)."
exit "$E_OK"
