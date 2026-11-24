#!/usr/bin/env bash
# ============================================================================
#  20-programs-guard.sh — every Programs.<key> used in hypr/*.lua must be
#  defined in hypr/modules/programs.lua. A missing key means a keybind that
#  silently does nothing on a fresh clone (typically a key that only exists in
#  the private, non-versioned private.lua). Comments are ignored.
#  Env (set by dotbackup): DOTBACKUP_PAYLOAD.
# ============================================================================
set -u
payload="${DOTBACKUP_PAYLOAD:?run by dotbackup}"
programs="$payload/hypr/modules/programs.lua"
[ -f "$programs" ] || exit 0

defined="$(sed -E 's/--.*$//' "$programs" | grep -oP '^\s+\K\w+(?=\s*=)' | sort -u)"
referenced="$(find "$payload/hypr" -name '*.lua' ! -name 'private.lua' ! -name 'private.example.lua' \
    -exec sed -E 's/--.*$//' {} + | grep -oP 'Programs\.\K\w+' | sort -u)"

missing="$(comm -13 <(printf '%s\n' "$defined") <(printf '%s\n' "$referenced"))"
if [ -n "$missing" ]; then
    for key in $missing; do
        echo "  ✘ Programs.$key is used in hypr/ but not defined in hypr/modules/programs.lua" >&2
    done
    exit 1
fi
exit 0
