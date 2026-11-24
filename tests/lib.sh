# shellcheck shell=bash
# ============================================================================
#  tests/lib.sh — tiny assertion helpers shared by the test files.
#  Every test runs in its own sandbox: HOME, XDG_* and git's global config
#  point inside a fresh temp folder, so nothing outside it can be touched.
# ============================================================================

# shellcheck disable=SC2034 # these are read by the test_*.sh files
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
DOTBACKUP="$ROOT/bin/dotbackup"
DISKBACKUP="$ROOT/bin/diskbackup"
INSTALL="$ROOT/install.sh"
REAL_PATH="$PATH"
REAL_HOME="$HOME"
REAL_USER="$(id -un)"
REAL_XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"

PASS=0
FAIL=0
FAILED=()
SANDBOXES=()

t_ok() {
    PASS=$((PASS + 1))
    printf '  ok    %s\n' "$1"
}

t_fail() {
    FAIL=$((FAIL + 1))
    FAILED+=("$1")
    printf '  FAIL  %s\n' "$1"
    if [ -n "${2:-}" ]; then printf '%s\n' "$2" | head -25 | sed 's/^/        | /'; fi
}

# run CMD… — stdin from /dev/null (never a terminal); sets OUT and RC
run() {
    OUT="$("$@" 2>&1 </dev/null)"
    RC=$?
}

# run_input INPUT CMD… — feeds INPUT (printf %b) on stdin
run_input() {
    local input="$1"
    shift
    OUT="$(printf '%b' "$input" | "$@" 2>&1)"
    RC=$?
}

# expect_rc NAME EXPECTED — checks the RC of the last run
expect_rc() {
    if [ "$RC" = "$2" ]; then t_ok "$1"; else t_fail "$1 (exit $RC, expected $2)" "$OUT"; fi
}

# expect NAME COMMAND… — passes when COMMAND succeeds
expect() {
    local name="$1"
    shift
    if "$@"; then t_ok "$name"; else t_fail "$name" "${OUT:-}"; fi
}

expect_out() { # NAME FIXED-STRING — the last output contains it
    if printf '%s' "$OUT" | grep -qF -- "$2"; then t_ok "$1"; else t_fail "$1 (output lacks: $2)" "$OUT"; fi
}

# A fingerprint of a tree: paths, sizes, mtimes, modes and link targets.
tree_hash() {
    find "$@" -printf '%p|%s|%T@|%m|%l\n' 2>/dev/null | LC_ALL=C sort | sha256sum | cut -d' ' -f1
}

new_sandbox() {
    SB="$(mktemp -d "${TMPDIR:-/tmp}/sumi-files-test.XXXXXX")"
    SANDBOXES+=("$SB")
    export HOME="$SB/home dir"
    mkdir -p "$HOME"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_CACHE_HOME="$HOME/.cache"
    export XDG_STATE_HOME="$HOME/.local/state"
    export XDG_DATA_HOME="$HOME/.local/share"
    export GIT_CONFIG_GLOBAL="$SB/gitconfig"
    export GIT_CONFIG_NOSYSTEM=1
    git config --global user.name "Sumi Test"
    git config --global user.email "test@example.invalid"
    git config --global init.defaultBranch main
    git config --global advice.detachedHead false
    unset SUMI_FILES_DIR SUMI_PRIVATE_PATTERNS SUMI_SHELL_DIR VISUAL EDITOR
    # sandbox paths may contain the real login (TMPDIR under it): use a fake one
    export SUMI_LOGIN="sumi-test-login"
    export NO_COLOR=1
    export PATH="$REAL_PATH"
}

# A PATH that has every tool the scripts use except the ones named.
path_without() {
    local dir="$SB/fakebin"
    rm -rf "$dir"
    mkdir -p "$dir"
    local tool
    for tool in fish bash sh env git rsync tar gzip cmp diff find sort sed grep xargs mktemp cat \
        cp mv rm ln mkdir chmod stat id date du cut head tail tr wc dirname basename readlink \
        realpath comm mountpoint sha256sum printf gitleaks shellcheck perl awk ls touch; do
        local skip=0 x
        for x in "$@"; do [ "$x" = "$tool" ] && skip=1; done
        [ "$skip" = 1 ] && continue
        local p
        p="$(PATH="$REAL_PATH" command -v "$tool" 2>/dev/null)" || continue
        ln -s "$p" "$dir/$tool"
    done
    printf '%s\n' "$dir"
}

cleanup_sandboxes() {
    [ "${KEEP_SANDBOX:-0}" = 1 ] && return
    local s
    for s in "${SANDBOXES[@]}"; do
        chmod -R u+rwX "$s" 2>/dev/null
        rm -rf -- "$s"
    done
}
