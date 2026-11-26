# sysupdate is a standalone tool now: bin/sysupdate in Sumi-Files, installed
# to ~/.local/bin by `install.sh --with-tools` (see `sysupdate --help`).
#
# This wrapper keeps `sysupdate`, `minimaru update` and SUPER+F2 working in
# any fish session, including one where ~/.local/bin is not on PATH yet.
function sysupdate --description "Full system update (pacman + AUR + Flatpak) with a verified end state"
    if command -q sysupdate
        command sysupdate $argv
    else if test -x ~/.local/bin/sysupdate
        ~/.local/bin/sysupdate $argv
    else
        echo "sysupdate: the tool is not installed — run ./install.sh --with-tools in Sumi-Files" >&2
        return 127
    end
end
