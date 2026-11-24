# -----------------------------------
# Hyprland plugin ABI resync
# -----------------------------------
#
# Built around the same rule as sysupdate: an exit code is not a state check.
# `hyprpm reload` happily prints
#
#     ✔ Loaded dynamic-cursors
#     ✔ Plugin load state ensured
#
# while the compositor has rejected the .so file and `hyprctl plugin list`
# answers "no plugins loaded". hyprpm is reporting that it asked, not that it
# succeeded. So every phase here ends by asking the compositor what is
# actually loaded, exactly as sysupdate ends every phase with `pacman -Qu`.
#
# ── Why this is not a step inside sysupdate ───────────────────────────────
# pacman replaces /usr/bin/Hyprland on disk, but the process keeps running the
# old code until the session restarts. hyprpm derives its build target from
# the RUNNING compositor — that is how it knows which commit of the Hyprland
# sources to clone — so rebuilding before the restart compiles the plugins
# against the ABI that was just replaced. The rebuild only becomes meaningful
# after the session comes back, which is after sysupdate has returned.
#
# ── Why -f is not optional ────────────────────────────────────────────────
# hyprpm caches Hyprland headers in headersRoot/ and decides they are current
# by comparing a stored hash against the running compositor. That hash gets
# refreshed even when the headers on disk do not, so hyprpm can hold headers
# generated against aquamarine 0.14, believe they are current, rebuild every
# plugin against them and report success. Observed on 2026-09-04: version.h
# said AQUAMARINE_VERSION "0.14.0" while state.toml claimed the aq_0.15 hash.
# This function therefore compares the headers to the compositor itself
# instead of trusting that check, and forces when they diverge.
#
# ── Never prefix hyprpm with sudo ─────────────────────────────────────────
# It elevates itself for the writes into /var/cache/hyprpm (its own message is
# "install will run as sudo") and refuses to run when already root. The cache
# being root-owned makes the wrong form look right, so this is guarded rather
# than left to the caller: the resulting error reads like a permission problem
# when it is the exact opposite.
#
# Exit codes (the shared ladder, see conf.d/report-ui.fish):
#     0   every enabled plugin is loaded
#     1   precondition failed, or declined before starting
#     2   usage error
#    10   finished with warnings (loaded, but the cache is stale)
#    20   finished with problems (a plugin still refuses to load)
#   127   a required command is missing

function hyprpmsync --description "Rebuild Hyprland plugins against the running compositor's ABI"
    # --check exists because the expensive half of this function is a C++
    # build of two 15 MB plugins. Diagnosing costs nothing and answers the
    # only question worth asking after an update, so it is worth a flag even
    # though every other function in this directory takes no arguments.
    set -l check 0
    for a in $argv
        switch $a
            case -h --help
                echo "hyprpmsync — Rebuild Hyprland plugins against the running compositor's ABI."
                echo "Usage: hyprpmsync [--check]"
                echo ""
                echo "  --check, -c   Diagnose only; never builds, never asks for a password."
                echo ""
                echo "Run it after restarting the session, not before: hyprpm builds"
                echo "against the compositor that is running, and pacman does not"
                echo "restart it."
                return 0
            case -c --check
                set check 1
            case '*'
                _rui_bad "hyprpmsync: unexpected argument '$a'"
                _rui_none "usage: hyprpmsync [--check]"
                return 2
        end
    end

    clear

    set -l W 40
    echo ""
    _rui_top $W
    _rui_row $W brwhite "󰐱  Hyprland Plugin Resync"
    _rui_mid $W
    _rui_row $W brblack "Rebuild + verify hyprpm plugins"
    _rui_bot $W
    echo ""

    _rui_have hyprctl "install hyprland"; or return $status
    _rui_have hyprpm "install hyprland"; or return $status

    # ── Pre-check: not root ───────────────────────────────────────────────
    # See the header. Checking SUDO_USER as well catches `sudo hyprpmsync`,
    # which would otherwise reach hyprpm as root and fail several screens
    # later with a message that points the wrong way.
    if test (id -u) -eq 0; or set -q SUDO_USER
        _rui_bad "Do not run hyprpmsync as root."
        _rui_none "hyprpm elevates itself for /var/cache/hyprpm and refuses to run as root."
        _rui_none "Re-run it as your normal user; it will ask for the password itself."
        _rui_pause
        return 1
    end

    # ── Pre-check: a compositor to ask ────────────────────────────────────
    # Everything below is a comparison against the running instance, so
    # without one there is no question to answer — not a degraded run, a
    # meaningless one.
    _rui_capture hyprctl version
    or begin
        _rui_bad "Could not capture hyprctl output."
        _rui_pause
        return 1
    end

    if test $__rui_rc -ne 0
        _rui_bad "No running Hyprland instance."
        _rui_none "hyprpm builds against the compositor that is running; start one first."
        _rui_pause
        return 1
    end

    set -l running_abi (string match -rg '^Version ABI string:\s*(\S+)' -- $__rui_out)
    if test -z "$running_abi"
        _rui_bad "hyprctl version did not report an ABI string."
        _rui_none "Unexpected hyprctl output — cannot verify anything against it."
        _rui_pause
        return 1
    end

    set -l root /var/cache/hyprpm/$USER
    if not test -d "$root"
        _rui_warn "No hyprpm cache at $root — nothing installed."
        _rui_verdict ok "Nothing to sync."
        _rui_pause
        return 0
    end

    # ══ Diagnosis ═════════════════════════════════════════════════════════
    _rui_section_plain cyan "󰋼" "ABI"

    set -l headers_abi (__hps_headers_abi "$root")
    set -l headers_stale 0

    _rui_val "Compositor" "$running_abi" 14
    if test -z "$headers_abi"
        _rui_warn "Could not read the cached headers — treating them as stale."
        set headers_stale 1
    else
        _rui_val "Headers" "$headers_abi" 14
        if test "$headers_abi" != "$running_abi"
            set headers_stale 1
            _rui_warn "Cached headers do not match the compositor."
            _rui_none (__hps_abi_diff "$headers_abi" "$running_abi")
        else
            _rui_ok "Cached headers match the compositor."
        end
    end

    # ── What hyprpm thinks is enabled ─────────────────────────────────────
    # Read from hyprpm's own state files rather than by parsing `hyprpm list`:
    # that output is colour-escaped and shaped for humans, while the state
    # files are the record hyprpm itself acts on. They are root-owned but
    # world-readable, so no elevation is needed to look.
    _rui_section_plain cyan "󰏓" "Plugins"

    set -l enabled (__hps_enabled "$root")
    if test (count $enabled) -eq 0
        _rui_ok "No plugins enabled — nothing to sync."
        _rui_verdict ok "Nothing to sync."
        _rui_pause
        return 0
    end

    set -l loaded (__hps_loaded)
    set -l missing
    for entry in $enabled
        set -l name (string split -m1 '|' -- $entry)[1]
        if contains -- $name $loaded
            _rui_ok "$name — loaded"
        else
            _rui_bad "$name — NOT loaded"
            set -a missing $entry
        end
    end

    # ── Verdict of the diagnosis ──────────────────────────────────────────
    if test (count $missing) -eq 0
        if test $headers_stale -eq 1
            _rui_warn "All plugins are loaded, but the header cache is stale."
            _rui_none "Harmless now; the next rebuild would compile against the wrong ABI."
            _rui_none "Run hyprpmsync (without --check) to refresh it."
            _rui_verdict warn "Plugins loaded, header cache stale."
            _rui_pause
            return 10
        end
        _rui_verdict ok "All enabled plugins are loaded."
        _rui_pause
        return 0
    end

    if test $check -eq 1
        echo ""
        _rui_none (count $missing)" plugin(s) not loaded. Re-run without --check to rebuild."
        _rui_verdict bad "Plugins out of sync with the compositor."
        _rui_pause
        return 20
    end

    # ══ Rebuild ═══════════════════════════════════════════════════════════
    _rui_section_plain magenta "󰑓" "Rebuild"
    echo ""
    _rui_none "This clones the Hyprland sources and compiles each plugin — a few minutes."
    _rui_none "hyprpm will ask for your password itself. Do not prefix it with sudo."
    echo ""

    if not _rui_confirm "Rebuild "(count $missing)" plugin(s) now?"
        echo ""
        _rui_verdict bad "Cancelled."
        _rui_pause
        return 1
    end
    echo ""

    # -f unconditionally: we are here because the state check failed, which
    # means hyprpm's own idea of freshness has already been proven wrong.
    hyprpm update -f
    set -l update_rc $status

    if test $update_rc -ne 0
        _rui_warn "hyprpm update exited $update_rc — verifying anyway."
    end

    hyprpm reload -n >/dev/null 2>&1

    # ══ Verification ══════════════════════════════════════════════════════
    # The point of the whole function. hyprpm has just claimed success; this
    # is the part that checks.
    _rui_section_plain cyan "󰄬" "Verification"

    set -l loaded_after (__hps_loaded)
    set -l still_missing
    for entry in $enabled
        set -l name (string split -m1 '|' -- $entry)[1]
        if contains -- $name $loaded_after
            _rui_ok "$name — loaded"
        else
            _rui_bad "$name — still not loaded"
            set -a still_missing $entry
        end
    end

    if test (count $still_missing) -eq 0
        _rui_verdict ok "All enabled plugins are loaded."
        _rui_pause
        return 0
    end

    # ── Why it still fails ────────────────────────────────────────────────
    # `hyprctl plugin load` on the .so is the only thing that prints the two
    # ABI strings side by side. hyprpm never surfaces them, which is what
    # turns this failure into a guessing game. Loading a plugin that is
    # already loaded would error, so only the missing ones are probed — and
    # if one of them happens to succeed here, that is a fix, not a side
    # effect.
    _rui_section_plain red "󰀦" "Diagnosis"
    for entry in $still_missing
        set -l parts (string split -m1 '|' -- $entry)
        set -l name $parts[1]
        set -l so $parts[2]

        if not test -r "$so"
            _rui_bad "$name — .so missing at $so"
            continue
        end

        _rui_capture hyprctl plugin load "$so"
        or continue

        set -l msg (string join ' ' -- $__rui_out $__rui_err)
        # [^,[:space:]] rather than \S: hyprctl writes the two strings as
        # "built against: <abi>, running compositor: <abi>", so \S+ swallows
        # the separating comma into the first one and the diff below then
        # reports a phantom difference in the last component.
        set -l built (string match -rg 'built against:\s*([^,[:space:]]+)' -- $msg)
        set -l runs (string match -rg 'running compositor:\s*([^,[:space:]]+)' -- $msg)

        if test -n "$built"; and test -n "$runs"
            _rui_bad "$name — ABI mismatch"
            _rui_none (__hps_abi_diff "$built" "$runs")
        else if string match -qir 'version mismatch' -- $msg
            # Some plugins throw a bare "Version mismatch" with no strings.
            _rui_bad "$name — ABI mismatch (plugin reported no versions)"
            _rui_none "Built against something other than $running_abi."
        else if string match -qir 'ok|loaded' -- $msg
            _rui_ok "$name — loaded on retry"
        else
            _rui_bad "$name — "(string trim -- "$msg")
        end
    end

    echo ""
    _rui_none "If the ABI still differs after a rebuild, the plugin has not been"
    _rui_none "updated for this Hyprland yet — check its repository, or disable it"
    _rui_none "with: hyprpm disable <name>"

    _rui_verdict bad (count $still_missing)" plugin(s) still not loading."
    _rui_pause
    return 20
end

# ── Helpers ───────────────────────────────────────────────────────────────
# Private to hyprpmsync, so they live here rather than in conf.d/report-ui.fish
# with the shared drawing helpers.

# Reconstructs the ABI string the cached headers would produce, so it can be
# compared against what the compositor reports.
#
# Hyprland composes that string from version.h as
#     <commit>_aq_<x.y>_hu_<x.y>_hg_<x.y>_hc_<x.y>_hlg_<x.y>
# taking only major.minor of each library. Rebuilding it here means the check
# compares like with like — the alternative, comparing hyprpm's stored hash,
# is the check that already failed us.
function __hps_headers_abi -a root
    set -l vh "$root/headersRoot/include/hyprland/src/version.h"
    test -r "$vh"; or return 1

    set -l src (cat "$vh" 2>/dev/null)
    test (count $src) -gt 0; or return 1

    set -l commit (string match -rg '^#define GIT_COMMIT_HASH\s+"([^"]+)"' -- $src)
    test -n "$commit"; or return 1

    set -l out "$commit"
    # Order is fixed by Hyprland, not alphabetical; keep the pairs together so
    # the tag and its macro cannot drift apart.
    for pair in "aq:AQUAMARINE" "hu:HYPRUTILS" "hg:HYPRGRAPHICS" "hc:HYPRCURSOR" "hlg:HYPRLANG"
        set -l tag (string split ':' -- $pair)[1]
        set -l macro (string split ':' -- $pair)[2]
        set -l ver (string match -rg "^#define $macro"'_VERSION\s+"(\d+\.\d+)' -- $src)
        test -n "$ver"; or return 1
        set out "$out"_"$tag"_"$ver"
    end
    echo $out
end

# Names the components that differ between two ABI strings, so the report can
# say "aquamarine 0.14 → 0.15" instead of printing two 70-character hashes and
# leaving the reader to diff them by eye.
function __hps_abi_diff -a a b
    set -l fa (string split '_' -- $a)
    set -l fb (string split '_' -- $b)

    if test "$fa[1]" != "$fb[1]"
        echo "Hyprland commit differs: "(string sub -l 9 -- $fa[1])" → "(string sub -l 9 -- $fb[1])
        return 0
    end

    # After the commit the fields are tag/version pairs, so they advance two
    # at a time; a differing count means an unrecognised shape and is reported
    # rather than half-parsed.
    if test (count $fa) -ne (count $fb)
        echo "ABI strings have different shapes: $a vs $b"
        return 0
    end

    set -l names aq aquamarine hu hyprutils hg hyprgraphics hc hyprcursor hlg hyprlang
    set -l hits
    for i in (seq 2 2 (math (count $fa) - 1))
        set -l tag $fa[$i]
        set -l va $fa[(math $i + 1)]
        set -l vb $fb[(math $i + 1)]
        test "$va" = "$vb"; and continue

        set -l long $tag
        for j in (seq 1 2 (count $names))
            if test "$names[$j]" = "$tag"
                set long $names[(math $j + 1)]
                break
            end
        end
        set -a hits "$long $va → $vb"
    end

    if test (count $hits) -eq 0
        echo "ABI strings differ but no component could be isolated."
    else
        echo (string join ", " $hits)
    end
end

# Enabled plugins, as "name|/path/to/plugin.so" lines.
#
# Parses hyprpm's per-repository state.toml directly. A repository can ship
# more than one plugin, so each file holds one section per plugin plus a
# [repository] section of git metadata that must not be mistaken for one.
function __hps_enabled -a root
    # find rather than a glob: an unmatched wildcard is an error in fish, and
    # "no plugins installed" is a normal state, not an error.
    for f in (find "$root" -mindepth 2 -maxdepth 2 -name state.toml 2>/dev/null | sort)
        set -l dir (dirname "$f")
        set -l section ""
        set -l enabled 0
        set -l filename ""

        for line in (cat "$f" 2>/dev/null)
            set -l s (string trim -- $line)

            set -l sec (string match -rg '^\[([^]]+)\]$' -- $s)
            if test -n "$sec"
                # Flush the section that just ended before starting the next.
                if test -n "$section"; and test $enabled -eq 1; and test -n "$filename"
                    echo "$section|$dir/$filename"
                end
                set enabled 0
                set filename ""
                # [repository] is git metadata, not a plugin.
                if test "$sec" = repository
                    set section ""
                else
                    set section "$sec"
                end
                continue
            end

            test -n "$section"; or continue

            set -l v (string match -rg '^enabled\s*=\s*(\S+)' -- $s)
            if test -n "$v"
                test "$v" = true; and set enabled 1
                continue
            end
            set v (string match -rg "^filename\s*=\s*'([^']+)'" -- $s)
            test -n "$v"; and set filename "$v"
        end

        # Last section in the file has no following header to flush it.
        if test -n "$section"; and test $enabled -eq 1; and test -n "$filename"
            echo "$section|$dir/$filename"
        end
    end
end

# Names of the plugins the compositor currently has loaded.
#
# -j and a regex rather than jq: this is the one question the whole function
# rests on, and it should not fail because an optional dependency is absent.
function __hps_loaded
    hyprctl plugin list -j 2>/dev/null | string match -rg '"name":\s*"([^"]*)"'
end
