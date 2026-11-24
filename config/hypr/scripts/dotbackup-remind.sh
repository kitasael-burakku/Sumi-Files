#!/usr/bin/env bash
# ============================================================================
#  dotbackup-remind.sh — read-only reminder: notifies when the live config
#  has drifted from the dotfiles repository, so you remember to run dotbackup.
# ----------------------------------------------------------------------------
#  It never syncs, commits or pushes. The comparison itself is
#  `dotbackup --check` (Sumi-Files bin/dotbackup), which reads the same
#  manifest the real sync uses, so the two can never disagree about what
#  "drift" means. Exit codes of --check: 0 up to date, 2 drift, other = error.
#
#  Run by systemd/user/dotbackup-remind.timer (weekly). Silent no-op when
#  dotbackup isn't installed or has no repository configured.
# ============================================================================
set -u

command -v dotbackup >/dev/null 2>&1 || exit 0

dotbackup --check --quiet >/dev/null 2>&1
rc=$?

case "$rc" in
    0) ;;
    2)
        command -v notify-send >/dev/null 2>&1 && notify-send -u low -i document-save \
            "dotbackup" "Your config has drifted from the dotfiles repository — run 'dotbackup' when convenient."
        ;;
    *)
        logger -t dotbackup-remind "dotbackup --check failed with exit code $rc" 2>/dev/null || true
        ;;
esac
exit 0
