#!/usr/bin/env bash
# ============================================================================
#  10-privacy.sh — blocks the commit when a file git would commit contains
#  personal data. Also run by hooks/git/pre-commit, so a manual `git commit`
#  gets the same check as dotbackup.
# ----------------------------------------------------------------------------
#  Always checked (no setup needed):
#    · your literal home path (dotbackup stores it as @HOME@);
#    · your login name as a whole word, case-sensitive.
#  Also checked when the file exists — strings only you know about (device
#  names, real name, city…), kept OUTSIDE the repository:
#    ${XDG_CONFIG_HOME:-~/.config}/sumi-files/private-patterns
#  one fixed string per line, case-sensitive, '#' comments allowed.
#  Template: share/examples/private-patterns.
#
#  Why: the repository mirrors a live config, so a personal value removed from
#  the repo comes back on the next sync if it is still in ~/.config.
#  Env: DOTBACKUP_REPO (set by dotbackup; defaults to the current repository),
#  SUMI_PRIVATE_PATTERNS (another patterns file), SUMI_LOGIN (another login).
# ============================================================================
set -u
repo="${DOTBACKUP_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$repo" ] || { echo "10-privacy.sh: not inside a git repository" >&2; exit 1; }
patterns="${SUMI_PRIVATE_PATTERNS:-${XDG_CONFIG_HOME:-$HOME/.config}/sumi-files/private-patterns}"

list="$(mktemp)" || exit 1
trap 'rm -f "$list"' EXIT
if [ -f "$patterns" ]; then
    grep -vE '^[[:space:]]*(#|$)' "$patterns" | sed 's/[[:space:]]*$//' | grep -v '^$' > "$list"
fi

files=()
while IFS= read -r -d '' f; do files+=("$f"); done \
    < <(git -C "$repo" ls-files -z -co --exclude-standard)
[ "${#files[@]}" -gt 0 ] || exit 0
cd "$repo" || exit 1

hits=""
if [ -s "$list" ]; then
    hits+="$(printf '%s\0' "${files[@]}" | xargs -0r grep -nIF -f "$list" -- 2>/dev/null)"$'\n'
fi
case "$HOME" in /?*)
    hits+="$(printf '%s\0' "${files[@]}" | xargs -0r grep -nIF -e "$HOME/" -- 2>/dev/null)"$'\n' ;;
esac
login="${SUMI_LOGIN:-$(id -un 2>/dev/null)}"
case "$login" in
    ''|root|user|admin|test|dev|me|you) ;;   # too generic to mean anything
    *) hits+="$(printf '%s\0' "${files[@]}" | xargs -0r grep -nIwF -e "$login" -- 2>/dev/null)"$'\n' ;;
esac

hits="$(printf '%s' "$hits" | grep -v '^$' | sort -u)"
if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | head -20 >&2
    echo "  ✘ personal data found above (home path, login name or $patterns)" >&2
    echo "    move it to a non-versioned override (docs/CONFIGURATION.md § Personal values) and re-run" >&2
    exit 1
fi
exit 0
