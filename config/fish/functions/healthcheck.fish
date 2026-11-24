function healthcheck --description "System health report (memory, updates, services, disk, temps)"
    # These reports take no arguments. They used to accept and silently ignore
    # anything, so `healthcheck --help` ran the full report — while the other
    # functions in this set had started returning 2 for a bad argument. Same
    # contract everywhere now. Checked before `clear` so the message survives.
    # --json (rediseño 11C): la misma lógica, sin pantalla — JSON Lines para el Dashboard.
    set -l json 0
    if test (count $argv) -gt 0
        if contains -- $argv[1] -h --help
            echo "healthcheck — System health report: memory, updates, services, disk, temps."
            echo "Usage: healthcheck [--json]"
            echo "  --json   no screen: one JSON record per check, then a verdict (JSON Lines)"
            return 0
        else if test "$argv[1]" = --json -a (count $argv) -eq 1
            set json 1
        else
            _rui_bad "healthcheck: unexpected argument '$argv[1]'"
            _rui_none "usage: healthcheck [--json]"
            return 2
        end
    end

    set -g __hc_findings 0
    set -g __hc_unknown 0
    if test $json -eq 1
        set -g __rui_json 1
        set -g __rui_recs
        __healthcheck_body >/dev/null 2>&1
        set -l rc $status
        # rg ausente: el cuerpo no llegó a comprobar nada — es un fallo, no un veredicto
        if test $rc -eq 127
            _rui_rec healthcheck unknown "ripgrep (rg) is not installed"
            printf '%s\n' $__rui_recs
            set -e __rui_json __rui_recs
            return 127
        end
        set -e __rui_json
        _rui_json_emit health $__hc_findings $__hc_unknown
        set -e __rui_recs
        test $__hc_findings -gt 0 -o $__hc_unknown -gt 0; and return 10
        return 0
    end

    clear
    __healthcheck_body
    set -l rc $status
    test $rc -eq 127; and return 127
    if test $__hc_unknown -gt 0
        _rui_verdict warn "$__hc_findings finding(s); $__hc_unknown check(s) could not answer."
        _rui_pause
        return 10
    end
    if test $__hc_findings -gt 0
        _rui_verdict warn "$__hc_findings section(s) need attention."
        _rui_pause
        return 10
    end
    _rui_verdict ok "System is healthy."
    _rui_pause
    return 0
end

# El informe en sí: lo corren la terminal y `--json`. Deja los recuentos en
# __hc_findings / __hc_unknown y un `_rui_rec` por comprobación.
function __healthcheck_body

    # See the note in checkerrors: rg is used in several sections and
    # without it the report fills up with "command not found" instead of
    # failing once.
    _rui_have rg "pacman -S ripgrep"
    or return 127

    set -l W 52

    # Sections that reported something actionable, and sections whose query
    # could not run. The report used to end on an unconditional
    # "✓ Health check complete." and return 0 whatever it had just printed,
    # so a box with four failed services and a clean one were indistinguishable
    # to anything calling healthcheck.
    set -l findings 0
    set -l unknown 0

    # ── Banner ────────────────────────────────────────────────────────────────
    echo ""
    _rui_top $W
    _rui_row $W brwhite "󰒋  System Health Check"
    _rui_mid $W
    _rui_row $W brblack "System · Memory · Disk · Network · Temps"
    _rui_bot $W
    echo ""

    # ── System ────────────────────────────────────────────────────────────────
    _rui_section cyan "󰌢" "System"
    _rui_val "Host:"   (uname -n)
    _rui_val "Kernel:" (uname -r)
    _rui_val "Uptime:" (uptime -p)
    _rui_val "Shell:"  (basename $SHELL)
    _rui_rec System info (uname -n)" · kernel "(uname -r)" · "(uptime -p)

    # ── Memory ────────────────────────────────────────────────────────────────
    _rui_section cyan "󰍛" "Memory"
    free -h | awk '/Mem:/  { printf "  %-16s%s / %s\n", "RAM:", $3, $2 }
                  /Swap:/ { printf "  %-16s%s / %s\n", "Swap:", $3, $2 }'
    if swapon --show=NAME,SIZE,USED,TYPE 2>/dev/null | rg -q "zram"
        swapon --show=NAME,SIZE,USED,TYPE | rg "zram" | awk '{printf "  %-16s%s  used %s\n", "zram:", $2, $3}'
    else
        _rui_none "zram not detected."
    end
    _rui_rec Memory info (free -h | awk '/Mem:/ { printf "RAM %s / %s", $3, $2 } /Swap:/ { printf " · swap %s / %s", $3, $2 }')

    # ── Updates ───────────────────────────────────────────────────────────────
    _rui_section yellow "󰚰" "Updates"
    # Declared out here on purpose: a "set -l" inside the if would be
    # scoped to that block and wouldn't be visible further down.
    set -l pacman_updates "?"
    set -l aur_updates "?"

    # checkupdates and the AUR helper's -Qua exit non-zero for "nothing pending" AND
    # for "the query failed", and both used to be piped straight into wc -l —
    # so a network outage or an unreadable database rendered as a confident
    # "0 pending". stderr is what separates the two; "?" means the check could
    # not answer, which is not the same claim as zero.
    if command -q checkupdates
        # These queries exit non-zero for "nothing pending" too, so
        # stderr is the discriminator here, not the status.
        if _rui_capture checkupdates; and test (count $__rui_err) -eq 0
            set pacman_updates (count $__rui_out)
        end
    end

    # Same preference as sysupdate and the AUR shortcuts.
    set -l aur_helper ""
    if command -q yay
        set aur_helper yay
    else if command -q paru
        set aur_helper paru
    end

    if test -n "$aur_helper"
        if _rui_capture $aur_helper -Qua; and test (count $__rui_err) -eq 0
            set aur_updates (count $__rui_out)
        end
    end

    _rui_val "Pacman:" "$pacman_updates pending"
    _rui_val "AUR:"    "$aur_updates pending"

    if test "$pacman_updates" = "?" -o "$aur_updates" = "?"
        _rui_warn "Could not determine pending updates."
        set unknown (math $unknown + 1)
        _rui_rec Updates unknown "Could not determine pending updates" "pacman: $pacman_updates · AUR: $aur_updates"
    else if test "$pacman_updates" -eq 0 -a "$aur_updates" -eq 0
        _rui_ok "System is up to date."
        _rui_rec Updates ok "System is up to date"
    else
        _rui_warn "Updates available."
        set findings (math $findings + 1)
        _rui_rec Updates finding "Updates available" "pacman: $pacman_updates · AUR: $aur_updates"
    end

    # ── Orphans ───────────────────────────────────────────────────────────────
    _rui_section yellow "󰮯" "Orphan packages"
    set -l orphans
    if not _rui_capture pacman -Qtdq
        _rui_warn "Could not run the orphan query (no temporary file)."
        set unknown (math $unknown + 1)
        _rui_rec "Orphan packages" unknown "Could not run the orphan query"
    else if test (count $__rui_err) -gt 0
        _rui_warn "Could not query orphans: $__rui_err[1]"
        set unknown (math $unknown + 1)
        _rui_rec "Orphan packages" unknown "Could not query orphans" $__rui_err[1]
    else if set orphans $__rui_out; and test (count $orphans) -gt 0
        printf "  %s\n" $orphans
        set findings (math $findings + 1)
        _rui_rec "Orphan packages" finding (count $orphans)" orphan package(s)" $orphans
    else
        _rui_ok "No orphan packages."
        _rui_rec "Orphan packages" ok "No orphan packages"
    end

    # ── Pacnew / Pacsave ──────────────────────────────────────────────────────
    _rui_section yellow "󰘓" "Pacnew / Pacsave"
    _rui_pacfiles
    if test (count $__rui_pacfiles) -gt 0
        printf "  %s\n" $__rui_pacfiles
        set findings (math $findings + 1)
        _rui_rec "Pacnew / Pacsave" finding (count $__rui_pacfiles)" file(s) to merge" $__rui_pacfiles
    else if test (count $__rui_pacfiles_blind) -gt 0
        _rui_warn "Cannot confirm — unreadable: "(string join ", " $__rui_pacfiles_blind)
        set unknown (math $unknown + 1)
        _rui_rec "Pacnew / Pacsave" unknown "Cannot confirm: some folders are unreadable" $__rui_pacfiles_blind
    else
        _rui_ok "No pacnew/pacsave files."
        _rui_rec "Pacnew / Pacsave" ok "No pacnew/pacsave files"
    end

    # ── Failed services ───────────────────────────────────────────────────────
    _rui_section red "󰋊" "Failed services"
    # systemctl exits 0 when there is nothing to report, so unlike the pacman
    # query verbs a non-zero status here means the query itself failed — and
    # the old 2>/dev/null capture turned that into "No failed system services."
    if not _rui_capture systemctl --failed --no-legend
        _rui_warn "Could not query system services (no temporary file)."
        set unknown (math $unknown + 1)
        _rui_rec "Failed services" unknown "Could not query system services"
    else if test $__rui_rc -ne 0
        _rui_warn "Could not query system services: "(test (count $__rui_err) -gt 0; and echo $__rui_err[1]; or echo "exit $__rui_rc")
        set unknown (math $unknown + 1)
        _rui_rec "Failed services" unknown "Could not query system services" (test (count $__rui_err) -gt 0; and echo $__rui_err[1]; or echo "exit $__rui_rc")
    else if test (count $__rui_out) -gt 0
        set -l failed_system $__rui_out
        printf "  %s\n" $failed_system
        set -l tpm ""
        if printf "%s\n" $failed_system | rg -q "tpm2|pcrproduct"
            _rui_warn "TPM failures detected — known issue."
            set tpm "TPM failures — known issue"
        end
        set findings (math $findings + 1)
        _rui_rec "Failed services" finding (count $failed_system)" failed system unit(s)" $failed_system $tpm
    else
        _rui_ok "No failed system services."
        _rui_rec "Failed services" ok "No failed system services"
    end

    if not _rui_capture systemctl --user --failed --no-legend
        _rui_warn "Could not query user services (no temporary file)."
        set unknown (math $unknown + 1)
        _rui_rec "Failed services" unknown "Could not query user services"
    else if test $__rui_rc -ne 0
        _rui_warn "Could not query user services: "(test (count $__rui_err) -gt 0; and echo $__rui_err[1]; or echo "exit $__rui_rc")
        set unknown (math $unknown + 1)
        _rui_rec "Failed services" unknown "Could not query user services" (test (count $__rui_err) -gt 0; and echo $__rui_err[1]; or echo "exit $__rui_rc")
    else if test (count $__rui_out) -gt 0
        printf "  %s\n" $__rui_out
        set findings (math $findings + 1)
        _rui_rec "Failed services" finding (count $__rui_out)" failed user unit(s)" $__rui_out
    else
        _rui_ok "No failed user services."
        _rui_rec "Failed services" ok "No failed user services"
    end

    # ── Boot errors ───────────────────────────────────────────────────────────
    _rui_section red "󰍛" "Boot errors"
    # journalctl exits 0 when nothing matches, so a non-zero status is a real
    # failure. Piping it straight into `count` swallowed that: an unreadable
    # journal produced error_count=0 and a confident "No critical boot errors."
    set -l boot_errors
    set -l error_count "?"

    if not _rui_capture journalctl -b -p 3 --no-pager
        _rui_warn "Could not read the journal (no temporary file)."
        set unknown (math $unknown + 1)
        _rui_rec "Boot errors" unknown "Could not read the journal"
    else if test $__rui_rc -ne 0
        _rui_warn "Could not read the journal: "(test (count $__rui_err) -gt 0; and echo $__rui_err[1]; or echo "exit $__rui_rc")
        set unknown (math $unknown + 1)
        _rui_rec "Boot errors" unknown "Could not read the journal" (test (count $__rui_err) -gt 0; and echo $__rui_err[1]; or echo "exit $__rui_rc")
    else
        set boot_errors $__rui_out
        # "count $boot_errors" would count lines, not events: a single coredump
        # (systemd-coredump) prints a backtrace of hundreds of lines as ONE
        # event, so a couple of waybar/swaync crashes inflated this to three
        # digits even with only 10 real entries in the journal.
        # --output=json emits one JSON object per event on a single line (the
        # multiline MESSAGE goes in with \n escaped inside), so counting that
        # gives the real number of events.
        if _rui_capture journalctl -b -p 3 --no-pager --output=json; and test $__rui_rc -eq 0
            set error_count (count $__rui_out)
        end
    end

    _rui_val "Errors:" "$error_count this boot"

    if test "$error_count" = "?"
        _rui_none "Event count unavailable."
    else if test "$error_count" -eq 0
        _rui_ok "No critical boot errors."
        _rui_rec "Boot errors" ok "No critical boot errors"
    else if printf "%s\n" $boot_errors | rg -q "tpm2|pcrproduct|TPM key integrity"
        _rui_warn "Critical errors are mostly TPM — known issue."
        set -l non_tpm (printf "%s\n" $boot_errors | rg -i "random-seed|bluetooth|filesystem|nvme|amdgpu|i/o error|failed to mount|corrupt" | head -12)
        if test (count $non_tpm) -gt 0
            printf "  %s\n" $non_tpm
        else
            _rui_none "No extra non-TPM errors."
        end
        _rui_rec "Boot errors" finding "$error_count critical error(s) this boot, mostly TPM (known issue)" $non_tpm
    else
        set -l shown (printf "%s\n" $boot_errors | rg -i "fail|error|random-seed|bluetooth|filesystem|nvme|amdgpu" | head -12)
        printf "%s\n" $shown
        # sin coincidencias con el filtro, el registro lleva las primeras líneas (la pantalla, como antes)
        test (count $shown) -eq 0; and set shown $boot_errors[1..8]
        _rui_rec "Boot errors" finding "$error_count critical error(s) this boot" $shown
    end
    # "?" is already counted as unknown above; only a real non-zero count is a
    # finding, so an unavailable count never silently becomes either verdict.
    if test "$error_count" != "?"; and test "$error_count" -ne 0
        set findings (math $findings + 1)
    end

    # ── Disk ──────────────────────────────────────────────────────────────────
    #
    # Used to be "df -h / /boot", which was wrong for two reasons: /boot
    # isn't a separate mount here (only /boot/efi is), so df resolved both
    # paths to the same filesystem and the section printed "/" TWICE — and
    # a second disk never showed up at all.
    #
    # Now all real filesystems are auto-detected, excluding the pseudo-FS,
    # so a new disk or USB drive shows up on its own without touching the
    # function. --output instead of positional columns ($6): with a
    # long-named device df wraps the line and the positional awk gets thrown
    # off.
    _rui_section cyan "󰪺" "Disk"
    set -l disks (df -h --output=target,used,size,pcent \
        -x tmpfs -x devtmpfs -x efivarfs -x overlay -x squashfs 2>/dev/null | tail -n +2)
    for l in $disks
        printf "%s\n" $l | awk '{printf "  %-16s%s used of %s (%s)\n", $1":", $2, $3, $4}'
    end
    _rui_rec Disk info (count $disks)" filesystem(s)" \
        (printf "%s\n" $disks | awk '{printf "%s: %s used of %s (%s)\n", $1, $2, $3, $4}')

    # ── Cache overview ────────────────────────────────────────────────────────
    _rui_section brblack "󰪺" "Cache overview"
    set -l caches
    for d in ~/.cache ~/.config ~/.local/share/Trash
        if test -d $d
            set -l sz (du -sh $d 2>/dev/null | cut -f1)
            _rui_val (string replace $HOME "~" $d)":" $sz
            set -a caches (string replace $HOME "~" $d)": $sz"
        end
    end
    _rui_rec "Cache overview" info (string join " · " -- $caches)

    # ── Network ───────────────────────────────────────────────────────────────
    _rui_section cyan "󰛟" "Network"
    set -l nets
    if command -q nmcli
        set nets (nmcli -t -f DEVICE,TYPE,STATE connection show --active 2>/dev/null)
        printf "%s\n" $nets | awk -F: '{printf "  %-16s%-12s%s\n", $1, $2, $3}'
        set nets (string replace -a ':' ' · ' -- $nets)
    else
        set nets (ip -brief addr | awk '{printf "%s %s\n", $1, $3}')
        printf "  %s\n" $nets
    end
    _rui_rec Network info (count $nets)" active connection(s)" $nets

    # ── Temperatures ──────────────────────────────────────────────────────────
    _rui_section cyan "󰔏" "Temperatures"
    if command -q sensors
        set -l temps (sensors | rg -i "tctl|edge|composite|junction|temp"; or sensors)
        printf "%s\n" $temps
        _rui_rec Temperatures info (count $temps)" sensor line(s)" $temps
    else
        _rui_none "sensors not installed."
        _rui_rec Temperatures info "sensors is not installed"
    end

    # ── Recuentos ─────────────────────────────────────────────────────────────
    # Resumen para el dashboard de Sumi Shell (Fase 10.d): epoch|hallazgos|desconocidos.
    # Lo escriben la terminal y --json por igual.
    printf '%s|%s|%s' (date +%s) $findings $unknown > "$HOME/.cache/minimaru-health-summary" 2>/dev/null
    set -g __hc_findings $findings
    set -g __hc_unknown $unknown
    return 0
end
