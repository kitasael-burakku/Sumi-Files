# -----------------------------------
# Full Arch Linux update routine
# -----------------------------------
#
# The rule this file is built around: "pacman exited 0" does NOT mean
# "the system is up to date". When an upgrade candidate can't be resolved,
# pacman asks
#
#     :: The following package cannot be upgraded due to unresolvable dependencies:
#           hyprtoolkit
#     :: Do you want to skip the above package for this upgrade? [y/N]
#
# and if you say yes it drops that package, upgrades everything else and
# exits 0. That is correct pacman behaviour — it is a normal rolling-release
# transition, not an error — but it means the exit code alone can never
# justify printing "System fully updated".
#
# So every phase here is followed by a *state check* that asks the package
# database what is still pending, instead of trusting the exit code or
# scraping the transcript:
#
#     pacman -Syu  →  verify  →  yay -Sua  →  verify  →  post-checks
#
# Exit codes (see __su_state_* below):
#     0   SUCCESS               nothing pending, nothing to flag
#    10   UPDATED_WITH_WARNINGS updated; pacnew / orphans / reboot pending
#    20   SKIPPED_PACKAGES      updates still pending (blocked or held)
#    30   CANCELLED             aborted once the update was under way
#    40   FAILURE               pacman or yay actually failed
#     1   PRECONDITION          could not start, or declined before starting
#
# The numbers ascend with severity, because __su_worst picks the higher of two
# states and the AUR phase is gated on `state -ge $st_failure`. CANCELLED and
# FAILURE used to be 40 and 30 — the wrong way round — so declining pacman's
# transaction scored 40, cleared that gate, and skipped the entire AUR phase
# while announcing "the official phase left the base system in a failed state".
# Answering `n` at the pacman prompt is a normal thing to do, so that silently
# cost an AUR update every time. Keep severity and numeric order in agreement.
#
# Ctrl+C is not in that list on purpose: fish tears down the whole function
# when a foreground child dies on SIGINT, so sysupdate stops mid-run and
# returns 130 without printing anything. That is the one interruption path
# this function cannot narrate, and it is also the only one it doesn't need
# to — silence can't be mistaken for success.

function sysupdate --description "Full system update (pacman + AUR) with a verified end state"
    # Takes no arguments; rejecting them rather than ignoring them keeps the
    # contract identical across every function in this directory.
    if test (count $argv) -gt 0
        if contains -- $argv[1] -h --help
            echo "sysupdate — Full system update (pacman + AUR) with a verified end state."
            echo "Usage: sysupdate   (takes no arguments)"
            return 0
        end
        _rui_bad "sysupdate: unexpected argument '$argv[1]'"
        _rui_none "usage: sysupdate   (takes no arguments)"
        return 2
    end

    clear

    set -l W 40

    # State codes. Kept as locals with names rather than bare integers so
    # the precedence comparison at the bottom reads as an ordering — and the
    # values must stay in that order, since __su_worst and the AUR gate both
    # compare them numerically. See the exit-code table at the top of the file.
    set -l st_success 0
    set -l st_warnings 10
    set -l st_skipped 20
    set -l st_cancelled 30
    set -l st_failure 40

    # ── Banner ────────────────────────────────────────────────────────────────
    echo ""
    _rui_top $W
    _rui_row $W brwhite "󰮯  Full Arch Update Routine"
    _rui_mid $W
    _rui_row $W brblack "Updates Pacman + AUR (yay / paru)"
    _rui_bot $W
    echo ""

    # ── Pre-check: free space ─────────────────────────────────────────────
    # This is the only thing here that can leave the system worse off than
    # before: if / fills up mid-transaction, pacman is left half-done.
    # Packages get downloaded to /var/cache/pacman/pkg, which lives on /.
    set -l min_bytes (math "2 * 1024 * 1024 * 1024")
    set -l avail (df -B1 --output=avail / 2>/dev/null | tail -1 | string trim)

    if test -n "$avail"; and test "$avail" -lt "$min_bytes"
        _rui_bad "Low space on /: "(math -s1 "$avail / 1024 / 1024 / 1024")" GiB free (minimum 2 GiB)"
        _rui_none "Free up space first — try cleantrash or quickcache."
        _rui_pause
        return 1
    end
    _rui_ok "Space on /: "(math -s1 "$avail / 1024 / 1024 / 1024")" GiB free"

    # ── Pre-check: database lock ──────────────────────────────────────────
    # Without this the run dies several screens later inside pacman with a
    # "unable to lock database" wall of text. Checking first turns that into
    # one line, and — more to the point — into a precondition failure rather
    # than something that looks like an update failure.
    set -l dbpath (pacman-conf DBPath 2>/dev/null)
    test -n "$dbpath"; or set dbpath /var/lib/pacman/
    if test -e "$dbpath/db.lck"
        _rui_bad "Pacman database is locked ($dbpath/db.lck)"
        _rui_none "Another package manager is running — wait for it to finish."
        _rui_pause
        return 1
    end
    _rui_ok "Pacman database is free"
    echo ""

    if not _rui_confirm "Continue?"
        echo ""
        set_color red
        echo "  Cancelled."
        set_color normal
        _rui_pause
        # 1, not $st_cancelled: nothing was started, which is the same
        # situation cleantrash and quickcache report as 1. $st_cancelled is
        # reserved for aborting once the update is already under way.
        return 1
    end
    echo ""

    # ── Detect AUR helper ──────────────────────────────────────────────────
    set -l aur_helper ""
    if command -q yay
        set aur_helper yay
    else if command -q paru
        set aur_helper paru
    else
        set_color red
        echo "  No AUR helper found (yay or paru required)."
        set_color normal
        _rui_pause
        return 1
    end

    # yay's review menus are a deliberate safety net for AUR PKGBUILDs, but
    # they are yay spellings. paru names its review flags differently and
    # would abort on an unknown flag, so the extra arguments only go to yay.
    set -l aur_args -Sua
    if test "$aur_helper" = yay
        set aur_args $aur_args --diffmenu --editmenu
    end

    set -l state $st_success
    set -l failed_stage ""

    # ══ Phase 1 — official repositories ═══════════════════════════════════
    _rui_section_plain cyan "󰚰" "Pacman"
    echo ""
    sleep 0.1

    # Byte offset of the pacman log, so that afterwards we can read back
    # exactly what this run applied. Reading the log delta beats parsing the
    # -Syu transcript: it is pacman's own record, it survives a scrolled-off
    # terminal, and yay writes to the same log for the AUR half.
    set -l log_mark_pacman (__su_log_size)

    # pkexec: the password goes through the desktop's polkit agent. It leaves no
    # sudo timestamp behind, so the post-checks below only get root when some
    # other sudo (yay installing AUR packages, say) has warmed one.
    pkexec pacman -Syu
    set -l pacman_rc $status

    set -l pacman_applied (__su_log_applied $log_mark_pacman)
    set -l pacman_applied_known $status

    # ── State check after pacman ──────────────────────────────────────────
    # pacman -Qu is the authoritative "what is still out of date" answer: it
    # compares every installed package against the sync databases using
    # libalpm's own version comparator, which is the same code that decides
    # what -Syu would do. Crucially it reads the databases that -Syu just
    # refreshed, so no network round-trip and no second -Sy is needed, and it
    # ignores foreign packages — so its output is official repos only, with
    # AUR cleanly excluded.
    #
    # It is also the reason this whole function exists: after the run above
    # it still reports the package pacman was told to skip.
    __su_query pacman -Qu
    set -l pending_raw $__su_q_out
    set -l pending_broken 0
    if test (count $__su_q_err) -gt 0
        # pacman -Qu exits 1 both for "nothing pending" and for a real
        # failure; only stderr separates them.
        set pending_broken 1
    end

    if test $pacman_rc -eq 0
        _rui_ok "Pacman finished."
    else
        # A non-zero pacman is either a genuine failure or the user declining
        # the transaction, and pacman reports both as 1. The state check
        # disambiguates: if everything that is pending is still cleanly
        # resolvable, nothing was broken — the transaction was refused.
        if __su_all_resolvable $pending_raw
            _rui_warn "Pacman did not complete (exit $pacman_rc) — transaction declined or aborted."
            set state (__su_worst $state $st_cancelled)
        else
            _rui_bad "Pacman failed (exit $pacman_rc)."
            set state (__su_worst $state $st_failure)
        end
        set failed_stage "pkexec pacman -Syu"
    end

    if test "$pacman_applied_known" -eq 0
        set -l n (count $pacman_applied)
        if test $n -gt 0
            _rui_none "$n package operation(s) applied from official repos."
        else
            _rui_none "No official packages were changed."
        end
    end

    # ── Report packages still pending from official repos ─────────────────
    _rui_section_plain cyan "󰋼 " "Pending from official repos"

    set -l skipped_names
    if test $pending_broken -eq 1
        _rui_warn "Could not query pending updates: $__su_q_err[1]"
        set state (__su_worst $state $st_warnings)
    else if test (count $pending_raw) -eq 0
        _rui_ok "No packages left pending."
    else
        # Each line is "name oldver -> newver", plus a literal "[ignored]"
        # marker when pacman.conf holds the package back.
        for line in $pending_raw
            set -l f (string split -n ' ' -- $line)
            test (count $f) -ge 4; or continue
            set -l name $f[1]
            set -l old $f[2]
            set -l new $f[4]
            set -a skipped_names $name

            set_color yellow
            echo "  ⚠ $name $old → $new"
            set_color brblack
            if contains -- '[ignored]' $f
                echo "      Reason: held back by IgnorePkg/IgnoreGroup in pacman.conf"
            else
                echo "      Reason: "(__su_pending_reason $name)
            end
            set_color normal
        end
        set state (__su_worst $state $st_skipped)
        echo ""
        _rui_none "Not an error: a repo transition resolves itself on a later sync."
        _rui_none "Do not force these with -Rdd, --overwrite or manual symlinks."
    end

    # ══ Phase 2 — AUR ═════════════════════════════════════════════════════
    # Only skipped when the base system is in a *failed* state. Two things that
    # are NOT that, and must not reach this gate: packages left pending, which
    # is the normal mid-transition state of a rolling release; and a declined
    # transaction, which means the user said "not now" to pacman and has no
    # bearing on whether the AUR half can run. The state codes are ordered so
    # that only $st_failure clears this test — see the table at the top.
    _rui_section_plain magenta "" "AUR — $aur_helper"
    if test $state -ge $st_failure
        _rui_warn "Skipped: the official phase left the base system in a failed state."
        _rui_none "Fix the pacman phase first, then re-run sysupdate."
    else
        echo ""
        sleep 0.1

        set -l log_mark_aur (__su_log_size)
        $aur_helper $aur_args
        set -l aur_rc $status

        set -l aur_applied (__su_log_applied $log_mark_aur)
        set -l aur_applied_known $status

        if test $aur_rc -eq 0
            _rui_ok "$aur_helper finished."
        else
            # yay returns 1 for a genuine build failure and for "the user
            # said no" alike, so the exit code is recorded but the verdict
            # comes from the state check below.
            _rui_warn "$aur_helper exited $aur_rc — checking what is still pending."
            set failed_stage "$aur_helper $aur_args"
        end

        if test "$aur_applied_known" -eq 0
            set -l n (count $aur_applied)
            if test $n -gt 0
                _rui_none "$n package operation(s) applied from AUR."
            else
                _rui_none "No AUR packages were changed."
            end
        end

        # ── State check after AUR ─────────────────────────────────────────
        # yay -Qua is the AUR-side mirror of pacman -Qu: foreign packages
        # only, compared against the AUR RPC. Same exit-code caveat — 1 means
        # "no AUR updates" just as often as it means trouble — so once again
        # stderr is what separates the two.
        __su_query $aur_helper -Qua
        set -l aur_pending $__su_q_out

        if test (count $__su_q_err) -gt 0
            _rui_warn "Could not query AUR updates: $__su_q_err[1]"
            set state (__su_worst $state $st_warnings)
        else if test (count $aur_pending) -eq 0
            _rui_ok "No AUR packages left pending."
            # An AUR helper that exited non-zero but left nothing pending was
            # cancelled at a prompt, not broken.
            if test $aur_rc -ne 0
                set state (__su_worst $state $st_cancelled)
            end
        else
            for line in $aur_pending
                set -l f (string split -n ' ' -- $line)
                test (count $f) -ge 1; or continue
                set -a skipped_names "$f[1] (AUR)"

                set_color yellow
                if test (count $f) -ge 4
                    echo "  ⚠ $f[1] $f[2] → $f[4]  (AUR)"
                else
                    # Unexpected shape: show the helper's own line rather
                    # than a half-parsed version of it.
                    echo "  ⚠ $line  (AUR)"
                end
                set_color normal
            end
            if test $aur_rc -ne 0
                set state (__su_worst $state $st_failure)
            else
                set state (__su_worst $state $st_skipped)
            end
        end
    end

    # ══ Post-update checks ════════════════════════════════════════════════
    # These three things show up right after the update, and they're
    # exactly the data healthcheck already computes — but you had to
    # remember to run it separately. All three checks are read-only.
    _rui_section_plain cyan "󰋼" "Post-update"

    set -l dirty 0

    # ── .pacnew / .pacsave ────────────────────────────────────────────────
    # Shared with healthcheck via conf.d/report-ui.fish; both used to carry
    # their own copy of this scan and both had the same blind spots. The sudo
    # timestamp is still warm from the pacman phase, so the scan elevates here
    # without a second password prompt. See _rui_pacfiles for why it reports
    # "cannot confirm" rather than "clean" when it cannot read everything.
    _rui_pacfiles

    if test (count $__rui_pacfiles) -gt 0
        _rui_warn (count $__rui_pacfiles)" .pacnew/.pacsave file(s) — review with pacdiff"
        printf "      %s\n" $__rui_pacfiles
        set dirty 1
    else if test (count $__rui_pacfiles_blind) -gt 0
        _rui_warn "Cannot confirm — unreadable: "(string join ", " $__rui_pacfiles_blind)
        _rui_none "Re-run with a fresh sudo timestamp to scan root-only directories."
        set dirty 1
    else
        _rui_ok "No .pacnew/.pacsave files."
    end

    # ── Orphans ───────────────────────────────────────────────────────────
    # Reported, never removed. pacman -Qtdq exits 1 for "no orphans" and for
    # a database error alike, so stderr decides which of the two it was.
    __su_query pacman -Qtdq
    set -l orphans $__su_q_out
    if test (count $__su_q_err) -gt 0
        _rui_warn "Could not query orphans: $__su_q_err[1]"
        set dirty 1
    else if test (count $orphans) -gt 0
        _rui_warn (count $orphans)" package(s) left orphaned — cleantrash removes them"
        printf "      %s\n" $orphans
        set dirty 1
    else
        _rui_ok "No orphan packages."
    end

    # One read covering both phases: log_mark_pacman predates the whole run,
    # and yay drives pacman for the AUR install, so a single delta already
    # contains everything either phase applied.
    #
    # Hoisted out of the reboot branch below, because the Hyprland plugin
    # check needs the same list and reading the log twice could disagree with
    # itself if the log rotated in between.
    set -l all_applied (__su_log_applied $log_mark_pacman)

    # ── Pending reboot ────────────────────────────────────────────────────
    # Two tiers, because only one of them is actually provable.
    #
    # Required: the running kernel's module directory is gone. That is a
    # fact, not a guess — the kernel was replaced underneath the running
    # system and it can no longer load modules. Package-agnostic, so it works
    # the same with linux-cachyos, -lts or anything else.
    #
    # Recommended: this run upgraded something whose new code only takes
    # effect after a restart. That one cannot be proven (a new
    # linux-cachyos-lts does nothing for a running linux-cachyos), so it is
    # phrased as a recommendation and lists what triggered it, rather than
    # asserting a reboot is needed.
    set -l running (uname -r)
    if not test -d "/usr/lib/modules/$running"
        _rui_warn "Reboot required — running kernel $running no longer has modules on disk."
        set dirty 1
    else
        set -l triggers (__su_reboot_triggers $all_applied)
        if test (count $triggers) -gt 0
            _rui_warn "Reboot recommended — core components updated: "(string join ", " $triggers)
            set dirty 1
        else if test "$pacman_applied_known" -ne 0
            _rui_none "Reboot status unknown — could not read the pacman log."
        else
            _rui_ok "No reboot needed."
        end
    end

    # ── Hyprland plugins ───────────────────────────────────────────────
    # Same shape as the reboot check above, and read-only for the same reason:
    # report what was invalidated, never repair it.
    #
    # Here that is not a style choice, it is the only correct order. hyprpm
    # derives its build target from the RUNNING compositor — that is how it
    # knows which commit of the Hyprland sources to clone — and the running
    # compositor is still the pre-upgrade binary, because pacman replaced the
    # file on disk and not the process. Rebuilding from here would compile
    # every plugin against the ABI that was just replaced. hyprpmsync does it
    # after the session restarts, which is after this function has returned.
    set -l hypr_triggers (__su_hypr_triggers $all_applied)
    if test (count $hypr_triggers) -gt 0; and __su_has_plugins
        _rui_warn "Hyprland plugins invalidated — updated: "(string join ", " $hypr_triggers)
        _rui_none "Restart the session, then run hyprpmsync."
        set dirty 1
    end

    # ── Processes running replaced code ───────────────────────────────────
    # The general case of the two checks above, and the one that needs no list
    # of package names to maintain: it asks the kernel which running processes
    # still map a file that no longer exists. Read-only like the rest of this
    # section — it names what to restart and restarts nothing, because deciding
    # to drop a running session belongs to the person at the keyboard.
    __su_stale_procs

    if test (count $__su_stale) -gt 0
        _rui_warn (count $__su_stale)" process(es) running replaced code — restart them"
        printf "      %s\n" $__su_stale
        # Partial coverage still reports what it did find; it just cannot claim
        # the list is complete.
        if test "$__su_stale_blind" -gt 0
            _rui_none "$__su_stale_blind process(es) could not be inspected — there may be more."
        end
        set dirty 1
    else if test "$__su_stale_blind" -ne 0
        # Same contract as the .pacnew scan: an incomplete look is reported as
        # "cannot confirm", never as "clean".
        if test "$__su_stale_blind" -lt 0
            _rui_warn "Cannot confirm which processes run replaced code — the scan could not start."
        else
            _rui_warn "Cannot confirm — $__su_stale_blind process(es) could not be inspected."
            _rui_none "Re-run with a fresh sudo timestamp to cover root-owned services."
        end
        set dirty 1
    else
        _rui_ok "No process is running replaced code."
    end

    # ── Outside pacman's reach ────────────────────────────────────────────
    # Informational by design — see __su_foreign_bins for why this one does not
    # set dirty.
    __su_foreign_bins
    if test (count $__su_foreign) -gt 0
        _rui_none (count $__su_foreign)" binary/binaries outside pacman: "(string join ", " $__su_foreign)
        _rui_none "Not covered by this update — cargo installed them, cargo updates them."
    end

    if test $dirty -ne 0
        set state (__su_worst $state $st_warnings)
    end

    # ══ Verdict ═══════════════════════════════════════════════════════════
    echo ""
    set_color brblack
    printf "  ────────────────────────────────────────────────────\n"
    set_color normal

    switch $state
        case $st_success
            set_color green
            echo "  󰏖  System fully updated."
        case $st_warnings
            set_color yellow
            echo "  󰀦  System updated with warnings."
        case $st_skipped
            set_color yellow
            echo "  󰀦  System updated with skipped packages."
            # Guarded: `string join` with an empty list would fall back to
            # reading stdin and hang the function on the terminal.
            if test (count $skipped_names) -gt 0
                _rui_none (count $skipped_names)" package(s) still pending: "(string join ", " $skipped_names)
            end
        case $st_cancelled
            set_color red
            echo "  󰜺  System update cancelled."
            test -n "$failed_stage"; and _rui_none "Stopped at: $failed_stage"
        case $st_failure
            set_color red
            echo "  󰅚  System update failed."
            test -n "$failed_stage"; and _rui_none "Failed at: $failed_stage"
    end

    set_color brblack
    printf "  ────────────────────────────────────────────────────\n"
    set_color normal
    echo ""

    # SUPER+F2 runs this as `kitty -e fish -c sysupdate`, and kitty closes the
    # moment the command returns. Without this the verdict — including the
    # skipped-package list, which is the whole point of the state machine —
    # is drawn and destroyed in the same frame. Harmless elsewhere: _rui_pause
    # returns immediately when stdin is not a terminal.
    _rui_pause

    return $state
end

# ── Helpers ───────────────────────────────────────────────────────────────
# Private to sysupdate, so they stay here rather than in conf.d/report-ui.fish
# with the shared drawing helpers. Fish sources this whole file on the first
# `sysupdate`, so definition order does not matter.

# Runs a read-only query and records stdout, stderr and status separately.
#
# Every pacman/yay query verb used here (-Qu, -Qtdq, -Qua) exits 1 for BOTH
# "no results" and "real failure", so the exit code on its own cannot tell
# "no orphans" from "the database is unreadable" — and treating the second as
# the first is precisely how a broken system reports itself as clean. These
# tools stay silent on an empty result and write a diagnostic on a real
# failure, so stderr is the discriminator, and callers test it rather than
# the status.
#
# Fish cannot return arrays, hence the __su_q_* globals; every caller
# consumes them immediately, before the next __su_query overwrites them.
#
# A failure to even set the query up is reported through __su_q_err too, not
# only through the return value. That is deliberate: all three callers ask
# "did this work?" by testing __su_q_err, so returning early with every field
# empty read as a clean "nothing to report" — no pending packages, no orphans —
# which is the one answer this function must never fabricate. Putting the
# reason where the callers already look fixes it at the source instead of
# relying on three call sites to remember. _rui_capture solves the same problem
# the other way, by documenting that its return value must be checked.
function __su_query
    set -g __su_q_out
    set -g __su_q_err
    set -g __su_q_rc 0

    set -l errfile (mktemp -t sysupdate-query.XXXXXX)
    or begin
        set -g __su_q_err "could not create a temporary file for the query"
        set -g __su_q_rc 1
        return 1
    end

    set __su_q_out ($argv 2>$errfile)
    set __su_q_rc $status
    set __su_q_err (cat $errfile)
    rm -f $errfile
    # Explicit: without it the function's status is whatever `rm -f` returned,
    # which says nothing about the query.
    return 0
end

# Why is $pkg still pending after an upgrade run?
#
# Answered by asking libalpm to resolve that one upgrade: `pacman -Sp` is a
# pure dry run — no root, no network, no database writes, it just prints the
# URLs it would download. Exit 0 means the upgrade is satisfiable, so the
# package was skipped or declined rather than blocked; non-zero means the
# resolver itself refused, and its own message is the authoritative reason.
#
# This is real dependency resolution rather than grepping the -Syu transcript
# for a phrase, so it keeps working when pacman rewords its output, when the
# transcript has scrolled away, and when sysupdate is re-run later against an
# already-finished update.
function __su_pending_reason -a pkg
    set -l errfile (mktemp -t sysupdate-reason.XXXXXX)
    or begin
        echo "could not be determined"
        return 0
    end

    # Both streams into one file on purpose: pacman splits this message,
    # writing the generic "failed to prepare transaction" summary to stderr
    # but the line that actually names the unsatisfiable dependency to
    # stdout. Reading only stderr yields the useless half.
    pacman -Sp --print-format '%n' -- $pkg >$errfile 2>&1
    set -l rc $status
    set -l err (cat $errfile)
    rm -f $errfile

    if test $rc -eq 0
        echo "upgrade is satisfiable — skipped or declined during this run"
        return 0
    end

    for line in $err
        set -l dep (string match -rg "unable to satisfy dependency '([^']+)' required by" -- $line)
        if test -n "$dep"
            echo "unsatisfied dependency $dep"
            return 0
        end
        if string match -q '*are in conflict*' -- $line
            echo (string trim -- (string replace -r '^::\s*' '' -- $line))
            return 0
        end
    end

    # No pattern matched: quote pacman's own first diagnostic rather than
    # inventing a reason for it.
    for line in $err
        set -l clean (string trim -- (string replace -r '^(::|error:|warning:)\s*' '' -- $line))
        if test -n "$clean"
            echo $clean
            return 0
        end
    end

    echo "could not be determined"
end

# True when every pending package is still cleanly resolvable, i.e. nothing
# is blocked. Used to tell a declined transaction (pacman exits 1, but the
# system is intact and the upgrades are all still available) apart from a
# genuine failure.
function __su_all_resolvable
    for line in $argv
        set -l name (string split -n ' ' -- $line)[1]
        test -n "$name"; or continue
        if not pacman -Sp --print-format '%n' -- $name >/dev/null 2>&1
            return 1
        end
    end
    return 0
end

# Current size of the pacman log in bytes, or empty when it is unreadable.
function __su_log_size
    set -l log (pacman-conf LogFile 2>/dev/null)
    test -n "$log"; or set log /var/log/pacman.log
    test -r "$log"; or return 1
    wc -c <"$log" | string trim
end

# Package operations recorded after byte offset $argv[1], as "action name"
# lines. Returns non-zero when the answer is unknown, so callers can say
# "unknown" instead of "nothing happened" — those are not the same claim.
#
# Reading the log delta rather than the terminal transcript also means the
# AUR half is covered for free: yay drives pacman for the actual install, so
# its work lands in the same log.
function __su_log_applied -a offset
    test -n "$offset"; or return 1

    set -l log (pacman-conf LogFile 2>/dev/null)
    test -n "$log"; or set log /var/log/pacman.log
    test -r "$log"; or return 1

    set -l now (wc -c <"$log" | string trim)
    string match -qr '^\d+$' -- "$now"; or return 1
    # Log rotated or truncated mid-run: the offset no longer points at
    # anything meaningful, so report "unknown" rather than a wrong delta.
    test "$now" -lt "$offset"; and return 1

    tail -c +(math "$offset + 1") -- "$log" \
        | string replace -rf '.*\[ALPM\] (upgraded|installed|removed) (\S+) .*' '$1 $2'
    return 0
end

# Of the operations applied this run, the ones whose new code only takes
# effect after a restart.
function __su_reboot_triggers
    set -l hits
    for entry in $argv
        set -l f (string split -n ' ' -- $entry)
        test (count $f) -ge 2; or continue
        contains -- $f[1] upgraded installed; or continue
        set -l name $f[2]

        if string match -qr '^linux(-|$)' -- $name
            # Headers and docs ship no running code.
            string match -qr -- '-(headers|api-headers|docs)$' $name; and continue
            set -a hits $name
        else if string match -qr '^nvidia' -- $name
            set -a hits $name
        else if contains -- $name glibc systemd systemd-libs dbus mesa wayland openssl
            set -a hits $name
        end
    end

    # A package can appear once per phase; report each name once.
    for n in $hits
        echo $n
    end | sort -u
end

# Worst (highest) of two state codes. The states are ordered
# success < warnings < skipped < cancelled < failure, so a later clean phase
# can never downgrade what an earlier phase already found.
function __su_worst -a a b
    test "$a" -ge "$b"; and echo $a; or echo $b
end

# Of the operations applied this run, the ones that invalidate every compiled
# Hyprland plugin.
#
# Deliberately not just "hyprland": the ABI string a plugin is built against is
#
#     <hyprland commit>_aq_<x.y>_hu_<x.y>_hg_<x.y>_hc_<x.y>_hlg_<x.y>
#
# so a bump of aquamarine, hyprutils, hyprgraphics, hyprcursor or hyprlang
# invalidates every plugin on its own, without Hyprland moving at all. That is
# not a corner case — it is what happened on 2026-09-04: hyprland went
# 0.56.2-1 → 0.56.2-2.1, the same upstream commit rebuilt against aquamarine
# 0.15, and both installed plugins silently stopped loading. Watching only the
# hyprland package would have reported nothing worth mentioning.
#
# Kept separate from __su_reboot_triggers rather than folded into it: they
# answer different questions ("restart the machine" vs "rebuild the plugins"),
# they share only some packages, and merging them would make either warning
# fire for the other's reasons.
function __su_hypr_triggers
    for entry in $argv
        set -l f (string split -n ' ' -- $entry)
        test (count $f) -ge 2; or continue
        contains -- $f[1] upgraded installed; or continue
        if contains -- $f[2] hyprland aquamarine hyprutils hyprgraphics hyprcursor hyprlang
            echo $f[2]
        end
    end | sort -u
end

# Processes running code whose file was replaced on disk.
#
# This is the generalisation of the reboot and Hyprland-plugin checks above,
# and the only one of the three that is provable for *any* program. When pacman
# upgrades a package it replaces the file; a process that already mapped the old
# one keeps executing it, while every file it opens from then on comes from the
# new version. That mismatch is what killed swaync on 2026-09-10: gtk4 went
# 4.22.4 -> 4.22.5 at 13:48, swaync had been running since 13:41, and it
# segfaulted at 15:28 inside a mapping the kernel still listed as
# "/usr/lib/libgtk-4.so.1.2200.4 (deleted)".
#
# The criterion is deliberately narrow: a mapping that is EXECUTABLE and whose
# backing file is gone. That is exactly "running code that was replaced", and it
# is what separates this from a `(deleted)` grep, which also matches JIT memfds,
# deleted temp files and data files no running code will ever jump into. Data
# under /usr/share is excluded by the same test — replacing an icon theme does
# not corrupt a running process the way replacing a .so does.
#
# Package-agnostic on purpose. It knows nothing about gtk4, Qt, or which
# notification daemon is in use, so it keeps working across a migration from a
# GTK daemon to a Qt one, and for anything else installed later.
#
# Results land in __su_stale (display lines) and __su_stale_blind (how many
# processes could not be inspected), never merged: "nothing stale" and "could
# not look" are different claims and the caller has to be able to tell them
# apart.
function __su_stale_procs
    set -g __su_stale
    set -g __su_stale_blind 0

    set -l errfile (mktemp -t sysupdate-stale.XXXXXX)
    or begin
        # -1 means the scan never ran, which is not the same as a scan that
        # found nothing. Same rule as __su_query.
        set -g __su_stale_blind -1
        return 1
    end

    # addr perms offset dev inode pathname — anchored on the perms field
    # carrying 'x', and on a pacman-managed prefix. /home and /opt-less paths
    # are out of scope: sysupdate reports on what pacman just changed.
    set -l re '^[0-9a-f]+-[0-9a-f]+ [r-][w-]x[ps] .* /(usr|opt)/[^ ]+ \(deleted\)$'

    # Without elevation the root-owned daemons are simply invisible — 31 of 331
    # processes on this machine — so the scan elevates when a sudo timestamp is
    # still warm, exactly as _rui_pacfiles does, and reports the shortfall when
    # it is not. Since the pacman phase moved to pkexec that timestamp is no
    # longer guaranteed: `sudo -n` never prompts, so a read-only report does not
    # stop to ask for a password — it just says what it could not see. `command grep` bypasses the interactive
    # `grep --color=auto` wrapper, whose escape codes would corrupt the parse.
    set -l hits
    if sudo -n true 2>/dev/null
        set hits (sudo -n grep -HE $re /proc/*/maps 2>$errfile)
    else
        set hits (command grep -HE $re /proc/*/maps 2>$errfile)
    end

    # Only permission failures are blind spots. A process that exited during the
    # scan is not one: it is gone, and gone processes run no stale code.
    set -l errs (cat $errfile 2>/dev/null)
    rm -f $errfile
    set -g __su_stale_blind (count (string match -r 'Permission denied' -- $errs))

    test (count $hits) -gt 0; or return 0

    set -l pids
    for line in $hits
        set -l pid (string replace -r '^/proc/([0-9]+)/maps:.*$' '$1' -- $line)
        # /proc/self and /proc/thread-self match the glob too and alias a pid
        # already in the list; dropping the non-numeric ones removes them.
        string match -qr '^[0-9]+$' -- $pid; and set -a pids $pid
    end
    test (count $pids) -gt 0; or return 0

    for pid in (printf '%s\n' $pids | sort -un)
        set -l mine (string match -- "/proc/$pid/maps:*" $hits)
        set -l n (count $mine)

        # comm rather than cmdline: one short name, no argv to wrap the line.
        set -l name (string trim -- (cat /proc/$pid/comm 2>/dev/null))
        test -n "$name"; or set name "pid $pid"

        set -l file (string replace -r '.* (/[^ ]+) \(deleted\)$' '$1' -- $mine[1])
        set file (string replace -r '.*/' '' -- $file)

        if test $n -gt 1
            set -a __su_stale "$name (pid $pid) — $file, +"(math $n - 1)" more"
        else
            set -a __su_stale "$name (pid $pid) — $file"
        end
    end
    return 0
end

# Executables installed outside pacman's reach.
#
# Reported, never updated — and deliberately not a warning. `cargo install`
# drops binaries in ~/.cargo/bin where no package manager tracks them, so
# sysupdate structurally cannot cover them; lutgen is the case here, and it
# exists in neither the official repos nor the AUR, so this is a permanent
# condition rather than something to go fix. A permanent warning is how a
# report teaches you to stop reading its warnings, so this one states the
# coverage gap and leaves the verdict alone.
function __su_foreign_bins
    set -g __su_foreign

    set -l dir $HOME/.cargo/bin
    test -d "$dir"; or return 0

    for f in (find "$dir" -maxdepth 1 -type f -executable 2>/dev/null | sort)
        set -l base (string replace -r '.*/' '' -- $f)
        # rustup keeps its shims in the same directory when it manages itself.
        # They belong to `rustup update`, not to `cargo install`, so they are
        # not a coverage gap and listing them would be noise.
        contains -- $base cargo cargo-clippy cargo-fmt cargo-miri clippy-driver \
            rls rust-analyzer rust-gdb rust-gdbgui rust-lldb rustc rustdoc \
            rustfmt rustup
        and continue
        set -a __su_foreign $base
    end
    return 0
end

# True when hyprpm has at least one enabled plugin — i.e. when the warning
# above has anything to warn about.
#
# Reads hyprpm's own state files instead of parsing `hyprpm list`, whose output
# is colour-escaped and shaped for humans. The files are root-owned but
# world-readable, so this stays within the read-only contract of the
# post-update section: no elevation, nothing written.
#
# `find` rather than a glob, because an unmatched wildcard is an error in fish
# and "no plugins installed" is a perfectly normal state to be in.
function __su_has_plugins
    set -l root /var/cache/hyprpm/$USER
    test -d "$root"; or return 1

    for f in (find "$root" -mindepth 2 -maxdepth 2 -name state.toml 2>/dev/null)
        test -r "$f"; or continue
        if string match -qr '^\s*enabled\s*=\s*true' -- (cat "$f" 2>/dev/null)
            return 0
        end
    end
    return 1
end
