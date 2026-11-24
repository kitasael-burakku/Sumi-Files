if status is-interactive; and command -q zoxide
    zoxide init fish | source
end

# The rest of this file is pure alias/interactive convenience — without this
# guard, any fish script (including "dotbackup" before it was deliberately
# forced to "command ls") would inherit "ls" pointing to eza, etc.
if status is-interactive
    # ── Modern CLI Replacements ──────────────────────────────
    alias cat="bat --paging=never"
    alias less="bat"
    alias ls="eza --icons --group-directories-first"
    alias lah="eza -lah --icons --group-directories-first"
    alias la="eza -a --icons --group-directories-first"
    alias copy="cp -iv"
    alias copyr="cp -riv"
    alias remove="rm -iv"
    alias remover="rm -riv"

    # ── System Maintenance ───────────────────────────────────
    # pkexec, not sudo: the password is asked by the desktop's polkit agent
    # (Sumi Shell's `auth` dialog). In a bare TTY with no agent, pkexec falls
    # back to its own text prompt.
    alias mirrors="pkexec reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist"
    alias fixkeys="pkexec pacman -Syu archlinux-keyring"

    # ── Logs & Diagnostics ───────────────────────────────────
    alias failed="systemctl --failed"
    alias userfailed="systemctl --user --failed"
    # jerrors vive ahora en functions/jerrors.fish: pliega el ruido cosmético
    # conocido (TDX en CPU AMD, capacidades que ath12k no anuncia, la secuencia
    # auth→session de gkr-pam...) y lo CUENTA al final en vez de esconderlo.
    # El alias tenía que salir de aquí: conf.d se carga al arrancar la shell, así
    # que definía la función "jerrors" antes de que fish pudiera autocargar la de
    # functions/ — y una función ya definida gana, así que la nueva nunca se
    # habría visto. Mismo motivo por el que ec.fish vive en functions/.

    # ── Hardware & Monitoring ────────────────────────────────
    alias disks="lsblk -f"
    alias temps="watch -n 2 sensors"

    # ── Software Config ──────────────────────────────────────
    # All of this now lives in functions/ec.fish (with tab-completion:
    # "ec <TAB>"). The old names are kept as wrappers so muscle memory
    # doesn't break — adding a new config is one line in __ec_targets, not
    # another alias here.
    # NOTE: this list has to match __ec_targets in functions/ec.fish. It's
    # deliberately not derived from there — doing so would force loading
    # ec.fish on EVERY shell start just to read the names, and ec.fish lives
    # in functions/ specifically so it only loads when you actually use it.
    # The price is having to add the name on both sides.
    for __ec_name in hypr fish kitty hyprlock \
        cava fastfetch matugen starship quickshell
        alias ec$__ec_name="ec $__ec_name"
    end
    set -e __ec_name
end
