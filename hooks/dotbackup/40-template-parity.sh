#!/usr/bin/env bash
# ============================================================================
#  40-template-parity.sh — informational: every matugen template and its
#  *.static.* twin must declare the same identifiers. Never blocks a backup.
#  Env (set by dotbackup): DOTBACKUP_PAYLOAD.
# ============================================================================
set -u
payload="${DOTBACKUP_PAYLOAD:?run by dotbackup}"
check="$payload/hypr/scripts/check-template-parity.sh"
[ -f "$check" ] || exit 0
# Sumi Shell is a separate project: compare against the installed copy.
shell_dir="${SUMI_SHELL_DIR:-${DOTBACKUP_SOURCE:-$HOME/.config}/quickshell/sumi}"
out="$(MINIMARU_CONFIG_DIR="$payload" SUMI_SHELL_DIR="$shell_dir" bash "$check" 2>&1)"
if [ -n "$out" ]; then
    echo "  ⚠ template/static parity (informational):" >&2
    printf '%s\n' "$out" | sed 's/^/    /' >&2
fi
exit 0
