#!/usr/bin/env bash
# ============================================================================
#  30-keybinds-doc.sh — regenerates docs/KEYBINDS.txt from the repo's own
#  hypr/modules/keybinds.lua, never from private.lua, so private binds can't
#  be documented in the public reference.
#  Env (set by dotbackup): DOTBACKUP_REPO, DOTBACKUP_PAYLOAD.
# ============================================================================
set -u
repo="${DOTBACKUP_REPO:?run by dotbackup}"
payload="${DOTBACKUP_PAYLOAD:?run by dotbackup}"
gen="$payload/hypr/scripts/generate-keybinds-doc.sh"
[ -f "$gen" ] && [ -f "$payload/hypr/modules/keybinds.lua" ] || exit 0

KEYBINDS_LUA="$payload/hypr/modules/keybinds.lua" PRIVATE_LUA="" \
    OUT="$repo/docs/KEYBINDS.txt" bash "$gen" >/dev/null
