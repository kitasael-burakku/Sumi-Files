# ~/.config/fish/functions/minimaru.fish
# "minimaru" — unified CLI for the rice. Doesn't add any new logic underneath:
# it's glue over what already existed loose (healthcheck/quickcache/
# cleantrash/sysupdate as fish functions, theme.sh/systemd.sh/wallpaper
# as rofi scripts until 10.e retired them, check-template-parity.sh/generate-keybinds-doc.sh
# as checks in hypr/scripts/) — the idea is one single entry point instead
# of having to remember 8 loose names.
#
#   minimaru health          → healthcheck
#   minimaru health --json   → the same checks, no screen: JSON Lines (rediseño 11C)
#   minimaru clean           → quickcache (fast, no sudo)
#   minimaru clean --deep    → cleantrash (orphans + pacman cache, root via pkexec)
#   minimaru update          → sysupdate
#   minimaru theme           → the shell's visual profile picker
#   minimaru theme <scheme>  → sets the scheme directly (e.g. vibrant), shell or not
#   minimaru wall             → wallpaper strip (shell), or terminal fzf picker
#   minimaru mode             → Dashboard → Performance (rediseño 11A-1)
#   minimaru mode <perfil>    → sets the profile directly, shell or not
#   minimaru doctor           → template parity + config drift + keybinds drift
#                               + downed systemd services + orphans (read-only)
#   minimaru doctor --json    → the same checks, no screen: JSON Lines (11C)
#   minimaru doctor --fresh-clone → the other question: is every machine-specific
#                               value adapted to THIS machine? (read-only)
#   minimaru dashboard        → the shell's control centre
#   minimaru diskbackup        → mirror to the backup disk (repos + themes + private files)
#   minimaru diskbackup --check → just checks if anything's pending, writes nothing
#   minimaru menu              → peeks the shell's hover face (every button)
#
# Fase 10.d (2026-09-10): con Sumi Shell corriendo, `theme` / `mode <perfil>` /
# `wall` / `dashboard` / `menu` rutean por su IPC (`qs -c sumi ipc call …`).
# `wall --fzf` fuerza el picker de terminal. `health` y `doctor` escriben un
# resumen en ~/.cache/minimaru-{health,doctor}-summary que el dashboard del shell
# muestra.
#
# Fase 10.e (2026-09-17): los scripts de rofi se retiraron (docs/MIGRATION.md
# §«Sub-fase 10.e»), y con ellos el camino de reserva sin shell. Los verbos que
# sólo eran un menú (`theme`, `mode` y `dashboard` sin argumentos, `menu`) dicen
# cómo levantar el shell en vez de abrir rofi; los que hacen algo con argumentos
# (`theme <esquema>`, `mode <perfil>`, `wall`) siguen funcionando sin él.

# ¿Sumi Shell responde? El IPC contesta en ~25 ms; si el socket no está o el
# shell está reiniciando, `status` falla y caemos al camino sin shell.
function __minimaru_shell_up
    qs -c sumi ipc call sumi status >/dev/null 2>&1
end

# Un verbo del IPC del shell, en silencio. Falla si el cliente falla O si el
# verbo devuelve `false`: `qs ipc call` sale con 0 e imprime «false» cuando la
# función lo rechaza (medido 2026-09-18 con `mode bogus`), así que el código de
# salida solo no distingue «hecho» de «rechazado».
function __minimaru_ipc
    set -l out (qs -c sumi ipc call sumi $argv 2>/dev/null)
    or return 1
    test "$out" != false
end

# El suelo sin shell (10.e). Antes de la retirada, un menú sin shell abría su
# equivalente de rofi; ahora el camino es levantar el shell, y SUPER+SHIFT+R lo
# hace sin pasar por él (es un exec de Hyprland, no un atajo global). La segunda
# línea dice qué sí funciona sin shell para ese verbo.
function __minimaru_no_shell -a verb hint
    set_color red; echo "minimaru $verb: Sumi Shell isn't running"; set_color normal
    set_color brblack
    echo "    start it with SUPER+SHIFT+R, or: systemctl --user restart sumi-shell"
    test -n "$hint"; and echo "    $hint"
    set_color normal
    return 1
end

# Runs one of the hypr/rofi helper scripts and reports what happened.
#
# These used to be called as a bare `bash "$path"` whose output was captured
# and printed as if it were the check's own result — so a missing or
# non-executable script rendered "bash: No such file or directory" inside the
# report, styled like a finding. A check that cannot run is not a check that
# passed, and it is not a finding either; it has to say which.
#
# Prints the script's combined output on stdout and returns:
#   0   ran, clean (no output)
#   10  ran, produced findings
#   127 could not run
function __minimaru_script -a path
    # 11C: la salida también queda en __minimaru_script_out, para el registro de --json
    set -g __minimaru_script_out
    if not test -f "$path"
        _rui_warn "Check unavailable: "(string replace "$HOME" "~" "$path")" not found."
        return 127
    end

    set -l out (bash "$path" $argv[2..] 2>&1)
    set -l rc $status
    set -g __minimaru_script_out $out

    if test (count $out) -gt 0
        printf "%s\n" $out
        return 10
    end

    if test $rc -ne 0
        _rui_warn "Check exited $rc with no output: "(string replace "$HOME" "~" "$path")
        return 10
    end
    return 0
end

function __minimaru_doctor
    # --fresh-clone answers a different question from the daily health pass, so
    # it's its own report rather than a seventh section: after cloning you want
    # "what do I still owe this machine", not "is anything failing right now".
    if contains -- --fresh-clone $argv
        __minimaru_doctor_fresh_clone
        return $status
    end

    # --json (rediseño 11C): la misma lógica sin pantalla — JSON Lines para el Dashboard.
    if contains -- --json $argv
        set -g __rui_json 1
        set -g __rui_recs
        __minimaru_doctor_body >/dev/null 2>&1
        set -e __rui_json
        _rui_json_emit doctor $__dr_findings 0
        set -e __rui_recs
        test $__dr_findings -gt 0; and return 10
        return 0
    end

    clear
    __minimaru_doctor_body
    if test $__dr_findings -gt 0
        _rui_verdict warn "$__dr_findings section(s) need attention."
        _rui_pause
        return 10
    end
    _rui_verdict ok "Everything checked out."
    _rui_pause
    return 0
end

# El informe de doctor: lo corren la terminal y --json. Deja __dr_findings y un
# `_rui_rec` por comprobación.
function __minimaru_doctor_body
    set -l W 56

    echo ""
    _rui_top $W
    _rui_row $W brwhite "󰓙  minimaru doctor"
    _rui_mid $W
    _rui_row $W brblack "Parity · Drift · Keybinds · Services · Orphans"
    _rui_bot $W
    echo ""

    # Counts sections that reported something actionable, so the exit status
    # matches what is on screen instead of always being 0.
    set -l findings 0

    _rui_section cyan "󰃟" "Template/static parity (matugen)"
    __minimaru_script "$HOME/.config/hypr/scripts/check-template-parity.sh"
    switch $status
        case 0
            _rui_ok "All dynamic templates match their statics."
            _rui_rec "Template parity" ok "All dynamic templates match their statics"
        case 127
            set findings (math $findings + 1)
            _rui_rec "Template parity" unknown "Check unavailable: check-template-parity.sh not found"
        case '*'
            set findings (math $findings + 1)
            _rui_rec "Template parity" finding "Templates and statics differ" $__minimaru_script_out
    end

    _rui_section cyan "󰋩" "Config drift (cross-file references)"
    __minimaru_script "$HOME/.config/hypr/scripts/check-config-drift.sh"
    switch $status
        case 0
            _rui_ok "gtk.css, theme names, icon theme, symlinks, lock chain and retired pieces all check out."
            _rui_rec "Config drift" ok "gtk.css, theme names, icon theme, symlinks, lock chain and retired pieces all check out"
        case 127
            set findings (math $findings + 1)
            _rui_rec "Config drift" unknown "Check unavailable: check-config-drift.sh not found"
        case '*'
            set findings (math $findings + 1)
            _rui_rec "Config drift" finding "Cross-file references drifted" $__minimaru_script_out
    end

    _rui_section cyan "󰌌" "Keybinds documentation"
    set -l gen "$HOME/.config/hypr/scripts/generate-keybinds-doc.sh"
    if not test -f "$gen"
        _rui_warn "Check unavailable: generate-keybinds-doc.sh not found."
        set findings (math $findings + 1)
        _rui_rec "Keybinds documentation" unknown "Check unavailable: generate-keybinds-doc.sh not found"
    else if bash "$gen" --check >/dev/null 2>&1
        _rui_ok "KEYBINDS.txt is up to date with keybinds.lua."
        _rui_rec "Keybinds documentation" ok "KEYBINDS.txt is up to date with keybinds.lua"
    else
        _rui_warn "KEYBINDS.txt is outdated — run 'checkkeybinds --write'."
        set findings (math $findings + 1)
        _rui_rec "Keybinds documentation" finding "KEYBINDS.txt is outdated" "run 'checkkeybinds --write'"
    end

    _rui_section red "󰋊" "Downed systemd services"
    # systemctl exits 0 when nothing has failed, so a non-zero status means the
    # query itself failed. The old 2>/dev/null capture made that indistinguish-
    # able from a healthy system and printed "No failed services".
    set -l failed_sys
    set -l failed_usr
    set -l svc_unknown 0

    if _rui_capture systemctl --failed --no-legend; and test $__rui_rc -eq 0
        set failed_sys $__rui_out
    else
        set svc_unknown 1
    end
    if _rui_capture systemctl --user --failed --no-legend; and test $__rui_rc -eq 0
        set failed_usr $__rui_out
    else
        set svc_unknown 1
    end

    if test $svc_unknown -eq 1
        _rui_warn "Could not query systemd services — status unknown."
        set findings (math $findings + 1)
        _rui_rec "Failed services" unknown "Could not query systemd services"
    else if test (count $failed_sys) -eq 0 -a (count $failed_usr) -eq 0
        _rui_ok "No failed services (system or user)."
        _rui_rec "Failed services" ok "No failed services (system or user)"
    else
        printf "  %s\n" $failed_sys $failed_usr
        set findings (math $findings + 1)
        _rui_rec "Failed services" finding (math (count $failed_sys) + (count $failed_usr))" failed unit(s)" $failed_sys $failed_usr
    end

    _rui_section yellow "󰮯" "Orphan packages"
    # -Qtdq exits 1 for "no orphans" and for a database error alike, so the
    # old 2>/dev/null turned an unreadable database into a confident
    # "No orphan packages."
    if not _rui_capture pacman -Qtdq
        _rui_warn "Could not run the orphan query (no temporary file)."
        set findings (math $findings + 1)
        _rui_rec "Orphan packages" unknown "Could not run the orphan query"
    else if test (count $__rui_err) -gt 0
        _rui_warn "Could not query orphans: $__rui_err[1]"
        set findings (math $findings + 1)
        _rui_rec "Orphan packages" unknown "Could not query orphans" $__rui_err[1]
    else if test (count $__rui_out) -eq 0
        _rui_ok "No orphan packages."
        _rui_rec "Orphan packages" ok "No orphan packages"
    else
        printf "  %s\n" $__rui_out
        _rui_none "Clean up with: minimaru clean --deep"
        set findings (math $findings + 1)
        _rui_rec "Orphan packages" finding (count $__rui_out)" orphan package(s)" $__rui_out "Clean up with: minimaru clean --deep"
    end

    _rui_section cyan "󰋊" "Disk backup (diskbackup)"
    # diskbackup ships in Sumi-Files (bin/diskbackup) and is optional: it is
    # only on $PATH after `install.sh --with-tools` or a manual copy, so
    # degrade gracefully here, don't assume it's present.
    # Contract (docs/DISKBACKUP.md): --check exits 0 = up to date, 2 = pending
    # (pending lines start with "    ~ " or "    + "), 66 = not configured. command -v (not
    # test -x on a fixed path): search $PATH, not a hardcoded location —
    # the same way dotbackup is looked up.
    if not command -v diskbackup >/dev/null 2>&1
        _rui_none "diskbackup isn't installed (optional: Sumi-Files bin/diskbackup)."
        _rui_rec "Disk backup" info "diskbackup isn't installed (optional: Sumi-Files bin/diskbackup)"
    else
        set -l disk_out (diskbackup --check 2>&1)
        set -l disk_status $status
        switch $disk_status
            case 0
                _rui_ok "Repos, themes and private files up to date on the second disk."
                _rui_rec "Disk backup" ok "Repos, themes and private files up to date on the second disk"
            case 2
                _rui_warn "There are unbacked-up changes on the backup destination."
                # No ^ anchor: the actual line starts with the ANSI color
                # code before the spaces, so anchoring to the start never
                # matches.
                set -l pend (printf "%s\n" $disk_out | grep -E "    [~+] ")
                printf "%s\n" $pend
                _rui_none "Update with: minimaru diskbackup"
                set findings (math $findings + 1)
                _rui_rec "Disk backup" finding "Changes not backed up to the backup destination" $pend[1..12]
            case 66
                _rui_none "diskbackup has no configuration yet (see docs/DISKBACKUP.md)."
                _rui_rec "Disk backup" info "diskbackup isn't configured"
            case '*'
                _rui_warn "diskbackup can't reach its destination (not configured, not mounted or not initialised)."
                set findings (math $findings + 1)
                _rui_rec "Disk backup" unknown "diskbackup can't reach its destination (not configured, not mounted or not initialised)"
        end
    end

    # Resumen para el dashboard de Sumi Shell (Fase 10.d): epoch|nº de hallazgos.
    printf '%s|%s' (date +%s) $findings > "$HOME/.cache/minimaru-doctor-summary" 2>/dev/null
    set -g __dr_findings $findings
    return 0
end

function __minimaru_doctor_fresh_clone
    clear
    set -l W 56

    echo ""
    _rui_top $W
    _rui_row $W brwhite "󰃨  minimaru doctor --fresh-clone"
    _rui_mid $W
    _rui_row $W brblack "Machine-specific values, checked against this box"
    _rui_bot $W
    echo ""

    _rui_section cyan "󰇄" "Personal paths and hardware"
    __minimaru_script "$HOME/.config/hypr/scripts/check-personal-paths.sh"
    set -l rc $status
    if test $rc -eq 0
        _rui_ok "Everything machine-specific resolves on this machine."
    end

    echo ""
    _rui_none "Full list of what's hardcoded: docs/INSTALLATION.md § 9"
    _rui_none "For the daily health pass, run: minimaru doctor"

    if test $rc -ne 0
        _rui_verdict warn "Some machine-specific values still need adapting."
        _rui_pause
        return 10
    end
    _rui_verdict ok "Nothing left to adapt on this machine."
    _rui_pause
    return 0
end

function __minimaru_wall
    for dep in fd fzf
        if not command -q $dep
            set_color red; echo "minimaru wall: missing '$dep'"; set_color normal
            return 127
        end
    end

    set -l dirs ~/Pictures/Wallpapers ~/Videos/Wallpapers
    set -l selected (
        fd . $dirs --max-depth 1 --type f --color=never 2>/dev/null \
            | fzf --height=60% --border=rounded --prompt=" 󰸉 Wallpaper > " \
                  --preview 'file {}' --preview-window=down:2:wrap
    )

    # An empty selection means the picker was closed without choosing —
    # that is a cancellation, not a failure of the wallpaper machinery.
    test -n "$selected"; or return 1

    if not bash "$HOME/.config/hypr/scripts/apply-wallpaper.sh" "$selected"
        set_color red
        echo "minimaru wall: apply-wallpaper.sh failed for $selected"
        set_color normal
        return 1
    end

    # `disown` used to sit unconditionally after an `and`-guarded background
    # job: when apply-wallpaper.sh failed, no job was ever started and disown
    # printed "There are no suitable jobs" at the user. It only runs now on
    # the path that actually backgrounds something.
    nohup bash "$HOME/.config/hypr/scripts/matugen_reload.sh" "$selected" >/dev/null 2>&1 &
    disown
    return 0
end

function __minimaru_theme
    if test (count $argv) -eq 0
        # Con el shell: su superficie de perfil visual (Fase 10.c.4).
        if __minimaru_shell_up
            __minimaru_ipc open theme ""
            return $status
        end
        __minimaru_no_shell theme "or pass a scheme, which works without it: minimaru theme vibrant"
        return $status
    end

    set -l scheme "scheme-$argv[1]"
    set -l valid scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow scheme-tonal-spot scheme-vibrant
    if not contains -- "$scheme" $valid
        set_color red; echo "minimaru theme: unknown scheme '$argv[1]'"; set_color normal
        set_color brblack; echo "    valid: content expressive fidelity fruit-salad monochrome neutral rainbow tonal-spot vibrant"; set_color normal
        return 2
    end

    # Con el shell: mismo destino, por IPC (`services/Colors.setScheme`, ADR-28).
    if __minimaru_shell_up
        if __minimaru_ipc themeSet $argv[1]
            set_color green; echo "minimaru theme: visual profile → $scheme"; set_color normal
            return 0
        end
        set_color red; echo "minimaru theme: the shell refused '$argv[1]'"; set_color normal
        return 1
    end

    set -l state_home "$XDG_STATE_HOME"
    test -n "$state_home"; or set state_home "$HOME/.local/state"
    mkdir -p "$state_home/sumi-shell/theme"
    printf '%s' "$scheme" > "$state_home/sumi-shell/theme/scheme"
    touch "$state_home/sumi-shell/theme/enabled"
    set -l wall
    if test -f "$state_home/sumi-shell/current-wallpaper"
        set wall (cat "$state_home/sumi-shell/current-wallpaper")
    end
    if test -z "$wall" -o ! -f "$wall"
        set_color yellow; echo "minimaru theme: scheme saved ($scheme) — pick a wallpaper to generate colors."; set_color normal
        return 0
    end

    if not bash "$HOME/.config/hypr/scripts/matugen_reload.sh" "$wall"
        set_color red
        echo "minimaru theme: scheme saved ($scheme) but colour regeneration failed"
        set_color normal
        return 1
    end
    set_color green; echo "minimaru theme: visual profile → $scheme"; set_color normal
    return 0
end

function minimaru --description "Unified rice CLI — health/clean/update/theme/wall/doctor/menu"
    # Asking for help succeeds; running minimaru with nothing at all is still a
    # usage error, since it means the command was incomplete rather than
    # informational.
    set -l want_help 0
    contains -- $argv[1] -h --help; and set want_help 1

    # La versión de Sumi Shell (2026-11-07, SemVer): la que CORRE (IPC `api`) o, si no corre, la instalada
    # (version.json del usuario o del sistema). Su única fuente es sumi/version.json; aquí sólo se lee.
    if contains -- $argv[1] -V --version
        set -l running (timeout 2 qs -c sumi ipc call sumi api 2>/dev/null)
        set -l v (string match -r '"version":"([^"]*)"' -- "$running")[2]
        set -l a (string match -r '"apiVersion":([0-9]+)' -- "$running")[2]
        if test -n "$v"
            echo "minimaru (Minimaru rice CLI) · Sumi Shell $v (API $a, running)"
            return 0
        end
        set -l cfg $HOME/.config
        set -q XDG_CONFIG_HOME; and set cfg $XDG_CONFIG_HOME
        for f in $cfg/quickshell/sumi/version.json /etc/xdg/quickshell/sumi/version.json
            test -r $f; or continue
            set v (string match -r '"version"\s*:\s*"([^"]*)"' < $f)[2]
            set a (string match -r '"apiVersion"\s*:\s*([0-9]+)' < $f)[2]
            if test -n "$v"
                echo "minimaru (Minimaru rice CLI) · Sumi Shell $v (API $a, installed in "(dirname $f)", not running)"
                return 0
            end
        end
        echo "minimaru (Minimaru rice CLI) · Sumi Shell not found" >&2
        return 1
    end

    if test (count $argv) -eq 0; or test $want_help -eq 1
        set_color brwhite; echo "minimaru — unified rice CLI"; set_color normal
        echo ""
        echo "  minimaru health [--json]  system health check (--json: records for the shell, no screen)"
        echo "  minimaru clean            quick cache cleanup"
        echo "  minimaru clean --deep     orphans + pacman cache (pkexec)"
        echo "  minimaru update           full update (pacman + AUR)"
        echo "  minimaru theme [scheme]   visual profile — no argument opens the shell's picker"
        echo "  minimaru wall [--fzf]     wallpaper strip (shell), or fzf picker (--fzf / no shell)"
        echo "  minimaru mode [profile]   normal/focus/gaming/cinema/status — no argument opens Dashboard → Performance"
        echo "  minimaru doctor [--json]  parity + keybinds + services + orphans (--json: records, no screen)"
        echo "  minimaru dashboard        the shell's control centre"
        echo "  minimaru diskbackup       mirror to the backup disk (repos + themes + private files)"
        echo "  minimaru diskbackup --check   just checks if anything's pending, writes nothing"
        echo "  minimaru menu             peek every button of the shell"
        echo "  minimaru --version        the Sumi Shell version (running, or installed)"
        test $want_help -eq 1; and return 0
        return 2
    end

    set -l sub $argv[1]
    set -l rest $argv[2..]

    switch "$sub"
        case health
            healthcheck $rest
        case clean
            if contains -- --deep $rest
                cleantrash
            else
                quickcache
            end
        case update
            sysupdate
        case theme
            __minimaru_theme $rest
        case wall
            # `--fzf` fuerza el picker de terminal; si no, con el shell corriendo
            # se abre la tira de wallpapers (Fase 4), y sin el shell, el fzf.
            if contains -- --fzf $rest
                __minimaru_wall
            else if __minimaru_shell_up
                __minimaru_ipc open wallpaper ""
            else
                __minimaru_wall
            end
        case mode
            if test (count $rest) -eq 0
                # Sin argumento: el selector vive en Dashboard → Performance (rediseño
                # 11A-1; antes la fila MODE, 10.c.5); `mode.sh` de rofi se retiró en 10.e.
                if __minimaru_shell_up
                    __minimaru_ipc open performance ""
                else
                    __minimaru_no_shell mode "only the recovery fallback works without it: minimaru mode normal"
                end
            else if test "$rest[1]" = status
                # Mismo estado observado que Performance y el Centro de control.
                if __minimaru_shell_up
                    qs -c sumi ipc call sumi modes
                else
                    bash "$HOME/.config/hypr/scripts/desktop-mode.sh" status
                end
            else if __minimaru_shell_up
                if not __minimaru_ipc mode $rest[1]
                    echo "minimaru mode: request refused (busy, not ready, or unknown profile)" >&2
                    return 1
                end
                echo "Mode requested; run 'minimaru mode status' for the verified result."
            else if test "$rest[1]" = normal
                bash "$HOME/.config/hypr/scripts/desktop-mode.sh" normal
            else
                __minimaru_no_shell mode "focus, gaming and cinema require the shell; recovery: minimaru mode normal"
            end
        case doctor
            __minimaru_doctor $rest
        case diskbackup
            if not command -v diskbackup >/dev/null 2>&1
                set_color red; echo "minimaru diskbackup: not installed on this system"; set_color normal
                set_color brblack; echo "    it's optional: install it with Sumi-Files' install.sh --with-tools (see docs/DISKBACKUP.md)"; set_color normal
                return 127
            end
            diskbackup $rest
        case dashboard
            if __minimaru_shell_up
                __minimaru_ipc open dashboard ""
            else
                __minimaru_no_shell dashboard "its terminal pieces work without it: minimaru health · doctor · update"
            end
        case menu
            # Con el shell: asoma la cara hover del island (todos los botones).
            # El dmenu de rofi de antes se retiró en 10.e.
            if __minimaru_shell_up
                __minimaru_ipc peek ""
            else
                __minimaru_no_shell menu "run 'minimaru' with no arguments for the list of verbs"
            end
        case '*'
            set_color red; echo "minimaru: unknown subcommand '$sub'"; set_color normal
            set_color brblack; echo "    run 'minimaru' with no arguments to see the list"; set_color normal
            return 2
    end
end
