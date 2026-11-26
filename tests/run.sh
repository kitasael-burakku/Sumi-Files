#!/usr/bin/env bash
# ============================================================================
#  tests/run.sh — runs the Sumi-Files test suite. Safe anywhere: every test
#  works inside throw-away sandboxes (HOME, XDG_* and git's global config are
#  redirected), never touches ~/.config, real disks or real remotes.
#
#  Usage: tests/run.sh [dotbackup|diskbackup|sysupdate|install|static|privacy]...
#  KEEP_SANDBOX=1 keeps the temp folders for inspection.
# ============================================================================
set -u
cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1
# shellcheck source=tests/lib.sh
. ./lib.sh
for f in ./test_*.sh; do
    # shellcheck source=/dev/null
    . "$f"
done
trap cleanup_sandboxes EXIT

suites=("$@")
[ "${#suites[@]}" -gt 0 ] || suites=(static dotbackup diskbackup sysupdate install privacy)
for s in "${suites[@]}"; do
    declare -F "test_$s" >/dev/null || { echo "unknown suite: $s" >&2; exit 64; }
    "test_$s"
    echo
done

echo "passed: $PASS  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf '  - %s\n' "${FAILED[@]}"
    exit 1
fi
exit 0
