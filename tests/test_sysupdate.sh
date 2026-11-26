# shellcheck shell=bash
# tests/test_sysupdate.sh — bin/sysupdate against fake pacman, yay, pkexec,
# sudo, checkupdates and systemctl. Nothing real is ever upgraded: the PATH
# holds only the fakes plus basic tools, and every fake logs its argv to
# $SU_FAKE/calls so the tests can check what would have run.

# su_world [yay] — a fresh sandbox; with "yay", a fake AUR helper too.
su_world() {
    new_sandbox
    export SU_FAKE="$SB/fake"
    local bin="$SB/su-bin"
    SU_KREL="$(uname -r)"
    mkdir -p "$SU_FAKE/db/local" "$SU_FAKE/cache" "$SB/proc" "$SB/etc" "$bin" \
        "$SB/modules/$SU_KREL"
    : >"$SU_FAKE/pacman.log"
    : >"$SU_FAKE/calls"
    export SYSUPDATE_PROC="$SB/proc"
    export SYSUPDATE_MODULES="$SB/modules"
    export SYSUPDATE_PACNEW_ROOTS="$SB/etc"
    export SYSUPDATE_CONFIG="$SB/sysupdate.toml"
    export SYSUPDATE_RETRY_DELAY=0
    export CHECKUPDATES_DB="$SB/no-checkup-db"
    export WAYLAND_DISPLAY=wayland-test
    unset DISPLAY

    cat >"$bin/pacman" <<'EOF'
#!/usr/bin/env bash
F="$SU_FAKE"
echo "pacman $*" >>"$F/calls"
rcf() { cat "$F/$1" 2>/dev/null || echo 0; }
op="$1"; shift
case "$op" in
    -Syu)
        [ -f "$F/syu_log" ] && cat "$F/syu_log" >>"$F/pacman.log"
        [ -f "$F/qu_after" ] && cp "$F/qu_after" "$F/qu"
        exit "$(rcf syu_rc)" ;;
    -Qu) [ -s "$F/qu" ] && { cat "$F/qu"; exit 0; }; exit 1 ;;
    -Qi|-Q)
        [ "$1" = -- ] && shift
        if [ -f "$F/qi_$1" ]; then
            if [ "$op" = -Qi ]; then cat "$F/qi_$1"; else echo "$1 0.3.2-1"; fi
            exit 0
        fi
        echo "error: package '$1' was not found" >&2; exit 1 ;;
    -Qtdq) [ -s "$F/orphans" ] && { cat "$F/orphans"; exit 0; }; exit 1 ;;
    -Sup) exit "$(rcf sup_rc)" ;;
    -Sp)
        fmt=""; names=()
        while [ $# -gt 0 ]; do
            case "$1" in
                --print-format) fmt="$2"; shift 2 ;;
                --dbpath) shift 2 ;;
                --noconfirm) shift ;;
                --) shift; names+=("$@"); break ;;
                *) names+=("$1"); shift ;;
            esac
        done
        if [ "$fmt" = '%n' ]; then
            rc="$(rcf sp_rc)"
            if [ "$rc" != 0 ]; then
                echo "error: failed to prepare transaction (could not satisfy dependencies)" >&2
                echo ":: unable to satisfy dependency 'libfoo=2' required by ${names[0]}"
            fi
            exit "$rc"
        fi
        for n in "${names[@]}"; do awk -F'\t' -v n="$n" '$1 == n' "$F/sp_info" 2>/dev/null; done
        exit 0 ;;
esac
exit 0
EOF
    cat >"$bin/pacman-conf" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    DBPath) echo "$SU_FAKE/db/" ;;
    LogFile) echo "$SU_FAKE/pacman.log" ;;
    CacheDir) echo "$SU_FAKE/cache/" ;;
    *) exit 1 ;;
esac
EOF
    cat >"$bin/checkupdates" <<'EOF'
#!/usr/bin/env bash
echo "checkupdates $*" >>"$SU_FAKE/calls"
[ -f "$SU_FAKE/cu_fail" ] && { echo "==> ERROR: Cannot fetch updates" >&2; exit 1; }
[ -s "$SU_FAKE/qu" ] && { sed 's/ \[ignored\]$//' "$SU_FAKE/qu"; exit 0; }
exit 2
EOF
    cat >"$bin/pkexec" <<'EOF'
#!/usr/bin/env bash
echo "pkexec $*" >>"$SU_FAKE/calls"
[ -f "$SU_FAKE/pkexec_rc" ] && exit "$(cat "$SU_FAKE/pkexec_rc")"
exec "$@"
EOF
    cat >"$bin/sudo" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -n) exit 1 ;;
    -v) exit "$(cat "$SU_FAKE/sudo_v_rc" 2>/dev/null || echo 0)" ;;
esac
echo "sudo $*" >>"$SU_FAKE/calls"
exec "$@"
EOF
    cat >"$bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >>"$SU_FAKE/calls"
case " $* " in *" cat "*) [ -f "$SU_FAKE/unit" ] && exit 0; exit 1 ;; esac
exit 0
EOF
    if [ "${1:-}" = yay ]; then
        cat >"$bin/yay" <<'EOF'
#!/usr/bin/env bash
F="$SU_FAKE"
echo "yay $*" >>"$F/calls"
case "$1" in
    -Qua)
        [ -f "$F/aur_fail_once" ] && { rm -f "$F/aur_fail_once"; echo "-> request failed: connection reset by peer" >&2; exit 1; }
        [ -s "$F/aur" ] && { cat "$F/aur"; exit 0; }
        exit 1 ;;
    -Sua)
        [ -f "$F/yay_log" ] && cat "$F/yay_log" >>"$F/pacman.log"
        [ -f "$F/aur_after" ] && cp "$F/aur_after" "$F/aur"
        exit "$(cat "$F/yay_rc" 2>/dev/null || echo 0)" ;;
esac
exit 0
EOF
    fi
    chmod +x "$bin"/*
    local base
    base="$(path_without)"
    export PATH="$bin:$base"
}

su_called() { grep -qF -- "$1" "$SU_FAKE/calls"; }

# A quickshell built against Qt 6.12.0 while Qt 6.12.1 is pending.
su_qt_fixture() {
    cat >"$SU_FAKE/qi_quickshell" <<'EOF'
Name            : quickshell
Version         : 0.3.2-1
Depends On      : glibc  qt6-base  qt6-declarative  wayland
Required By     : None
EOF
    cat >"$SU_FAKE/qu" <<'EOF'
github-cli 2.105.0-1 -> 2.106.0-1
pyside6 6.12.0-3 -> 6.12.0-4
qt6-base 6.12.0-5 -> 6.12.1-1
qt6-declarative 6.12.0-4 -> 6.12.1-1
qt6ct 0.11-9 -> 0.11-10
shiboken6 6.12.0-3 -> 6.12.0-4
EOF
    printf '%s\n' \
        "$(printf 'github-cli\tgithub-cli\t2.106.0-1\tglibc')" \
        "$(printf 'pyside6\tpyside6\t6.12.0-4\tglibc python qt6-base qt6-declarative shiboken6')" \
        "$(printf 'qt6-base\tqt6-base\t6.12.1-1\tglibc libdrm')" \
        "$(printf 'qt6-declarative\tqt6-declarative\t6.12.1-1\tqt6-base')" \
        "$(printf 'qt6ct\tqt6ct\t0.11-10\tqt6-base qt6-svg')" \
        "$(printf 'shiboken6\tpyside6\t6.12.0-4\tglibc python')" >"$SU_FAKE/sp_info"
}

test_sysupdate() {
    echo "sysupdate"
    local saved_wayland="${WAYLAND_DISPLAY-}" saved_display="${DISPLAY-}"

    su_world yay
    run "$SYSUPDATE" --version
    local changelog_version
    changelog_version="$(grep -m1 -oP '^## sysupdate \K[0-9]+\.[0-9]+\.[0-9]+' "$ROOT/CHANGELOG.md")"
    expect "--version matches CHANGELOG ($changelog_version)" test "$OUT" = "sysupdate $changelog_version"
    run "$SYSUPDATE" --no-aur --aur-only
    expect_rc "--no-aur with --aur-only is a usage error" 2
    run "$SYSUPDATE" -i /etc/foo
    expect_rc "--ignore rejects paths" 2
    run "$SYSUPDATE" --json
    expect_rc "--json without check is a usage error" 2

    # ── nothing to do ──
    su_world yay
    run_input '' "$SYSUPDATE"
    expect_rc "nothing pending exits 0" 0
    expect_out "nothing pending says so" "Nothing to update."
    expect "nothing pending asks for no password" bash -c '! grep -q pkexec "$SU_FAKE/calls"'

    # ── a normal update ──
    su_world yay
    echo "foo 1.0-1 -> 1.1-1" >"$SU_FAKE/qu"
    : >"$SU_FAKE/qu_after"
    echo "[2026-11-25T10:00:00-0600] [ALPM] upgraded foo (1.0-1 -> 1.1-1)" >"$SU_FAKE/syu_log"
    touch "$SU_FAKE/unit"
    run_input 'y\n' "$SYSUPDATE"
    expect_rc "normal update exits 0" 0
    expect_out "normal update verdict" "System fully updated."
    expect "pacman ran through pkexec" su_called "pkexec pacman -Syu"
    expect "AUR phase skipped when nothing is pending there" bash -c '! grep -q "yay -Sua" "$SU_FAKE/calls"'
    expect "update counter refreshed" su_called "systemctl --user start --no-block updates-check.service"
    expect_out "one operation counted" "1 package operation applied"

    # ── declined at the first prompt ──
    su_world yay
    echo "foo 1.0-1 -> 1.1-1" >"$SU_FAKE/qu"
    run_input 'n\n' "$SYSUPDATE"
    expect_rc "declining before starting exits 1" 1
    expect "declining runs nothing" bash -c '! grep -q pkexec "$SU_FAKE/calls"'

    # ── pacman transaction declined: AUR still runs ──
    su_world yay
    echo "foo 1.0-1 -> 1.1-1" >"$SU_FAKE/qu"
    echo "bar 1-1 -> 2-1" >"$SU_FAKE/aur"
    : >"$SU_FAKE/aur_after"
    echo 1 >"$SU_FAKE/syu_rc"
    run_input 'y\n' "$SYSUPDATE"
    expect_rc "declined pacman transaction is CANCELLED (30)" 30
    expect_out "declined pacman says so" "declined at the prompt"
    expect "AUR phase still runs after a declined pacman" su_called "yay -Sua"

    # ── pkexec dialog dismissed ──
    su_world yay
    echo "foo 1.0-1 -> 1.1-1" >"$SU_FAKE/qu"
    echo "bar 1-1 -> 2-1" >"$SU_FAKE/aur"
    echo 126 >"$SU_FAKE/pkexec_rc"
    run_input 'y\nn\n' "$SYSUPDATE"
    expect_rc "dismissed authentication is CANCELLED (30)" 30
    expect_out "dismissed authentication says so" "Authentication cancelled"
    expect "no AUR phase after cancelled auth and 'n'" bash -c '! grep -q "yay -Sua" "$SU_FAKE/calls"'

    # ── sudo: failed authentication ──
    su_world
    echo "foo 1.0-1 -> 1.1-1" >"$SU_FAKE/qu"
    echo 1 >"$SU_FAKE/sudo_v_rc"
    run_input 'y\n' "$SYSUPDATE" --elevate sudo
    expect_rc "failed sudo authentication is CANCELLED (30)" 30
    expect "pacman never ran without a password" bash -c '! grep -q "pacman -Syu" "$SU_FAKE/calls"'

    # ── pacman failure: unresolvable ──
    su_world yay
    echo "foo 1.0-1 -> 1.1-1" >"$SU_FAKE/qu"
    echo "bar 1-1 -> 2-1" >"$SU_FAKE/aur"
    echo 1 >"$SU_FAKE/syu_rc"
    echo 1 >"$SU_FAKE/sup_rc"
    echo 1 >"$SU_FAKE/sp_rc"
    run_input 'y\n' "$SYSUPDATE"
    expect_rc "unresolvable pacman failure is FAILURE (40)" 40
    expect_out "AUR skipped after a failure" "Skipped: the official phase left the base system in a failed state."
    expect_out "pending reason quotes the dependency" "unsatisfied dependency libfoo=2"

    # ── interrupted transaction ──
    su_world
    echo "foo 1.0-1 -> 1.1-1" >"$SU_FAKE/qu"
    echo 1 >"$SU_FAKE/syu_rc"
    echo "[2026-11-25T10:00:00-0600] [ALPM] transaction started" >"$SU_FAKE/syu_log"
    run_input 'y\n' "$SYSUPDATE"
    expect_rc "half-done transaction is FAILURE (40)" 40
    expect_out "half-done transaction says so" "stopped in the middle of a transaction"

    # ── no AUR helper at all ──
    su_world
    echo "foo 1.0-1 -> 1.1-1" >"$SU_FAKE/qu"
    : >"$SU_FAKE/qu_after"
    run_input 'y\n' "$SYSUPDATE"
    expect_rc "works without an AUR helper" 0
    expect "pacman ran without an AUR helper" su_called "pacman -Syu"

    # ── AUR declined / build failed before installing ──
    su_world yay
    echo "bar 1-1 -> 2-1" >"$SU_FAKE/aur"
    echo 1 >"$SU_FAKE/yay_rc"
    run_input 'y\n' "$SYSUPDATE"
    expect_rc "AUR declined is CANCELLED (30), not FAILURE" 30
    expect_out "AUR declined says so" "installed nothing"
    expect "pacman phase skipped when only AUR is pending" bash -c '! grep -q "pacman -Syu" "$SU_FAKE/calls"'

    # ── AUR partly built ──
    su_world yay
    printf 'bar 1-1 -> 2-1\nbaz 1-1 -> 2-1\n' >"$SU_FAKE/aur"
    echo "baz 1-1 -> 2-1" >"$SU_FAKE/aur_after"
    echo "[2026-11-25T10:00:00-0600] [ALPM] upgraded bar (1-1 -> 2-1)" >"$SU_FAKE/yay_log"
    echo 1 >"$SU_FAKE/yay_rc"
    run_input 'y\n' "$SYSUPDATE"
    expect_rc "AUR partly failed is FAILURE (40)" 40

    # ── AUR RPC blip is retried ──
    su_world yay
    echo "bar 1-1 -> 2-1" >"$SU_FAKE/aur"
    touch "$SU_FAKE/aur_fail_once"
    run "$SYSUPDATE" check
    expect_out "AUR query retried after a reset" "AUR — yay (1)"

    # ── locks ──
    su_world
    echo "foo 1.0-1 -> 1.1-1" >"$SU_FAKE/qu"
    touch "$SU_FAKE/db/db.lck"
    run_input 'y\n' "$SYSUPDATE"
    expect_rc "stale lock exits 1" 1
    expect_out "stale lock is called stale" "no package manager is running"
    expect_out "stale lock shows the command" "sudo rm $SU_FAKE/db/db.lck"
    mkdir -p "$SB/proc/4242" && echo pacman >"$SB/proc/4242/comm"
    run_input 'y\n' "$SYSUPDATE"
    expect_out "busy lock names the process" "pacman (pid 4242) is running"

    # ── low space ──
    su_world
    echo "min_free_gib = 999999999" >"$SYSUPDATE_CONFIG"
    run_input 'y\n' "$SYSUPDATE"
    expect_rc "low space exits 1" 1
    expect_out "low space says so" "Low space on /"

    # ── configuration ──
    su_world
    echo 'elevate = "doas"' >"$SYSUPDATE_CONFIG"
    run "$SYSUPDATE" check
    expect_rc "invalid setting is a usage error" 2
    echo 'colour = true' >"$SYSUPDATE_CONFIG"
    run "$SYSUPDATE" check
    expect_rc "unknown setting only warns" 0
    expect_out "unknown setting is named" "unknown setting 'colour'"
    echo 'elevate = [' >"$SYSUPDATE_CONFIG"
    run "$SYSUPDATE" check
    expect_rc "broken TOML is a usage error" 2

    # ── watchlist: Qt bump without a quickshell rebuild ──
    su_world
    su_qt_fixture
    run "$SYSUPDATE" check
    expect_rc "risk found: check exits 10" 10
    expect_out "risk names quickshell" "quickshell 0.3.2-1 would run against new versions"
    expect_out "suggestion holds the Qt family and its rebuilds" "sysupdate -i 'qt6-*,pyside6,qt6ct,shiboken6'"
    run "$SYSUPDATE" check --json
    OUT="$(printf '%s' "$OUT" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(",".join(d["suggested_ignore"]), d["risky"], d["suggestion_verified"])')"
    expect "check --json carries the suggestion" test "$OUT" = "qt6-*,pyside6,qt6ct,shiboken6 True True"
    run "$SYSUPDATE" check -i 'qt6-*,pyside6,qt6ct,shiboken6'
    expect_rc "holding them back clears the risk" 0
    expect_out "held packages are listed" "Held back (--ignore / IgnorePkg): pyside6, qt6-base"

    su_world
    su_qt_fixture
    run_input 'i\n' "$SYSUPDATE"
    expect "[i] passes the suggestion to pacman" su_called "pacman -Syu --ignore qt6-*,pyside6,qt6ct,shiboken6"

    su_world
    su_qt_fixture
    echo "qt6-base 6.12.0-5 -> 6.12.0-6" >"$SU_FAKE/qu"
    run "$SYSUPDATE" check
    expect_rc "a pkgrel-only rebuild is not a risk" 0

    su_world
    su_qt_fixture
    printf '[watch]\n' >"$SYSUPDATE_CONFIG"
    run "$SYSUPDATE" check
    expect_rc "an empty [watch] turns the check off" 0

    # ── Flatpak: only when something is pending ──
    su_world
    cat >"$SB/su-bin/flatpak" <<'EOF2'
#!/usr/bin/env bash
echo "flatpak $*" >>"$SU_FAKE/calls"
[ "$1" = remote-ls ] && { cat "$SU_FAKE/flatpak_pending" 2>/dev/null; exit 0; }
exit 0
EOF2
    chmod +x "$SB/su-bin/flatpak"
    run_input 'y\n' "$SYSUPDATE"
    expect_rc "no Flatpak updates: nothing to do" 0
    expect "flatpak update not run when nothing is pending" bash -c '! grep -q "flatpak update" "$SU_FAKE/calls"'
    echo "org.example.App" >"$SU_FAKE/flatpak_pending"
    run_input 'y\n' "$SYSUPDATE"
    expect "flatpak update runs when something is pending" su_called "flatpak update"
    expect_out "pending Flatpak app listed" "org.example.App"
    : >"$SU_FAKE/calls"
    run_input 'y\n' "$SYSUPDATE" --no-flatpak
    expect "--no-flatpak skips it" bash -c '! grep -q "flatpak update" "$SU_FAKE/calls"'

    # ── post-checks ──
    su_world
    echo "linux 6.18-1 -> 6.18.1-1" >"$SU_FAKE/qu"
    : >"$SU_FAKE/qu_after"
    echo "[2026-11-25T10:00:00-0600] [ALPM] upgraded linux (6.18-1 -> 6.18.1-1)" >"$SU_FAKE/syu_log"
    printf 'old-lib\n' >"$SU_FAKE/orphans"
    touch "$SB/etc/pacman.conf.pacnew"
    run_input 'y\n' "$SYSUPDATE"
    expect_rc "post-check findings make it WARNINGS (10)" 10
    expect_out "kernel upgrade recommends a reboot" "Reboot recommended — core components updated: linux"
    expect_out "orphans reported" "1 package left orphaned"
    expect_out "pacnew reported" "pacman.conf.pacnew"

    su_world
    echo "foo 1.0-1 -> 1.1-1" >"$SU_FAKE/qu"
    : >"$SU_FAKE/qu_after"
    rm -rf "$SB/modules/$SU_KREL"
    run_input 'y\n' "$SYSUPDATE"
    expect_out "missing kernel modules require a reboot" "Reboot required"

    # ── still pending after the run, and -i forwarded ──
    su_world
    printf 'foo 1.0-1 -> 1.1-1\nqux 1-1 -> 2-1\n' >"$SU_FAKE/qu"
    echo "qux 1-1 -> 2-1" >"$SU_FAKE/qu_after"
    run_input 'y\n' "$SYSUPDATE" -i qux
    expect_rc "held package leaves SKIPPED (20)" 20
    expect "-i is forwarded to pacman" su_called "pacman -Syu --ignore qux"
    expect_out "held package is named as held on purpose" "Held back on purpose (1): qux"

    # ── checkupdates failing falls back to the local database ──
    su_world
    echo "foo 1.0-1 -> 1.1-1" >"$SU_FAKE/qu"
    touch "$SU_FAKE/cu_fail"
    run "$SYSUPDATE" check
    expect_rc "check works without checkupdates' network" 0
    expect_out "fallback source is stated" "pacman -Qu (local database"

    # leave the shell as the next suite expects it
    export PATH="$REAL_PATH"
    unset SU_FAKE SYSUPDATE_PROC SYSUPDATE_MODULES SYSUPDATE_PACNEW_ROOTS SYSUPDATE_CONFIG \
        SYSUPDATE_RETRY_DELAY CHECKUPDATES_DB WAYLAND_DISPLAY DISPLAY
    [ -n "$saved_wayland" ] && export WAYLAND_DISPLAY="$saved_wayland"
    [ -n "$saved_display" ] && export DISPLAY="$saved_display"
    return 0
}
