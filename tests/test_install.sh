# shellcheck shell=bash
# tests/test_install.sh — install.sh, run from a copy of this repository so
# the real manifest and payload are exercised without touching the original.

in_world() {
    new_sandbox
    RCOPY="$SB/sumi files"
    mkdir -p "$RCOPY"
    # the working tree as git would publish it (tracked + untracked, not
    # ignored), .git included. Ignored files — generated colours, local
    # completions, private files a dotbackup mirror leaves in config/ — would
    # make the results depend on the machine running the tests.
    (cd "$ROOT" && {
        find .git -print0
        git ls-files -z -co --exclude-standard -- . ':!:tests' | while IFS= read -r -d '' f; do
            if [ -e "$f" ] || [ -L "$f" ]; then printf '%s\0' "$f"; fi
        done
    } | tar --null --no-recursion -T - -cf -) | (cd "$RCOPY" && tar -xf -)
    TGT="$SB/target config"
    IN=("$RCOPY/install.sh" --target "$TGT" --skip-colors)
}

test_install() {
    echo "install.sh"

    in_world
    run "${IN[@]}" --help
    expect_rc "--help exits 0" 0
    run "${IN[@]}" --version
    expect_rc "--version exits 0" 0
    run "${IN[@]}" --bogus
    expect_rc "unknown option → 64" 64
    run "${IN[@]}" --target
    expect_rc "--target without a value → 64" 64
    run "${IN[@]}" --no-backup --yes
    expect_rc "--no-backup without --force → 64" 64
    run "${IN[@]}"
    expect_rc "not a terminal and no --yes → 64" 64
    run "$RCOPY/install.sh" --target "$RCOPY/config/x" --yes
    expect_rc "target inside the repository → 65" 65
    run "${IN[@]}" --only does-not-exist --yes
    expect_rc "--only matching nothing → 65" 65

    # ── Dry run ──
    mkdir -p "$TGT/kitty"
    printf 'mine\n' >"$TGT/kitty/kitty.conf"
    local before
    before="$(tree_hash "$TGT" "$HOME")"
    run "${IN[@]}" --dry-run --with-tools --enable-services
    expect_rc "--dry-run → 0" 0
    expect_out "--dry-run reports a replacement" "~ $TGT/kitty/kitty.conf"
    expect "--dry-run changed nothing" test "$before" = "$(tree_hash "$TGT" "$HOME")"

    # ── Install ──
    run "${IN[@]}" --yes
    expect_rc "install → 0" 0
    expect "hyprland.lua installed" test -f "$TGT/hypr/hyprland.lua"
    expect "systemd unit installed" test -f "$TGT/systemd/user/hyprland-session.service"
    expect "starship static installed" test -f "$TGT/starship.static.toml"
    expect "executable bit kept" test -x "$TGT/hypr/scripts/apply-wallpaper.sh"
    expect "@HOME@ rendered in qt5ct.conf" grep -qF "color_scheme_path=$HOME/.config/qt5ct/colors/minimaru.conf" "$TGT/qt5ct/qt5ct.conf"
    expect "no @HOME@ left anywhere" sh -c "! grep -rqF '@HOME@' '$TGT'"
    expect "replaced file moved to the backup" sh -c "grep -qx mine \"\$(find '$XDG_STATE_HOME/sumi-files/backups' -path '*kitty/kitty.conf')\""
    expect "new kitty.conf in place" sh -c "! grep -qx mine '$TGT/kitty/kitty.conf'"
    run "${IN[@]}" --yes
    expect_out "second run is a no-op" "0 new · 0 replaced"

    # ── Only what the repository ships ──
    in_world
    printf 'return { secret = true }\n' >"$RCOPY/config/hypr/modules/private.lua"
    run "${IN[@]}" --yes --only hypr
    expect "gitignored private.lua is not installed" test ! -e "$TGT/hypr/modules/private.lua"
    expect "--only hypr installed hypr" test -f "$TGT/hypr/hyprland.lua"
    expect "--only hypr skipped kitty" test ! -e "$TGT/kitty"

    # ── Link mode ──
    in_world
    run "${IN[@]}" --yes --link --only kitty --only qt5ct
    expect_rc "--link → 0" 0
    expect "plain file is a symlink" test -L "$TGT/kitty/kitty.conf"
    expect "templated file is a rendered copy" sh -c "test ! -L '$TGT/qt5ct/qt5ct.conf' && grep -qF '$HOME' '$TGT/qt5ct/qt5ct.conf'"

    # ── Tools ──
    in_world
    run "${IN[@]}" --yes --only kitty --with-tools --bin-dir "$SB/bin dir"
    expect_rc "--with-tools → 0" 0
    expect "dotbackup installed" test -x "$SB/bin dir/dotbackup"
    expect "copied dotbackup gets a settings file" grep -qF "repo = $RCOPY" "$XDG_CONFIG_HOME/sumi-files/dotbackup.conf"
    run "$SB/bin dir/dotbackup" --version
    expect_rc "installed dotbackup runs" 0

    # ── Round trip with the real manifest: install, then dotbackup sees no drift ──
    in_world
    run "${IN[@]}" --yes
    expect_rc "full install for the round trip" 0
    run "$RCOPY/bin/dotbackup" --repo "$RCOPY" --source "$TGT" --check
    expect_rc "dotbackup --check right after install → 0 (@HOME@ round-trips)" 0
    printf '\n# local edit\n' >>"$TGT/kitty/kitty.conf"
    run "$RCOPY/bin/dotbackup" --repo "$RCOPY" --source "$TGT" --check
    expect_rc "an edit in the installed tree → 2" 2
    expect_out "the edit is reported" "~ config/kitty/kitty.conf"

    # ── Audit 2026-11-24: --link + dotbackup must not destroy the repository ──
    in_world
    run "${IN[@]}" --yes --link
    expect_rc "--link install" 0
    local before_cfg
    before_cfg="$(tree_hash "$RCOPY/config")"
    run "$RCOPY/bin/dotbackup" --repo "$RCOPY" --source "$TGT" --check
    expect_rc "dotbackup --check after --link → 0" 0
    run "$RCOPY/bin/dotbackup" --repo "$RCOPY" --source "$TGT" --yes --no-snapshot --skip-hooks
    expect_rc "dotbackup --yes after --link → 0" 0
    expect "repo file is still a regular file" test -f "$RCOPY/config/kitty/kitty.conf" -a ! -L "$RCOPY/config/kitty/kitty.conf"
    expect "payload byte-for-byte unchanged" test "$before_cfg" = "$(tree_hash "$RCOPY/config")"
    expect "live config never got @HOME@ back" sh -c "! grep -rqF '@HOME@' '$TGT'"
    run "${IN[@]}" --yes --link
    expect_out "re-running --link is a no-op" "0 new · 0 replaced"

    # stow-style: a whole folder of the target links into the repository
    in_world
    mkdir -p "$TGT"
    ln -s "$RCOPY/config/kitty" "$TGT/kitty"
    before_cfg="$(tree_hash "$RCOPY/config")"
    run "${IN[@]}" --yes --link --only kitty
    expect_rc "stow-style target folder → 0" 0
    expect "repository left intact" test "$before_cfg" = "$(tree_hash "$RCOPY/config")"
    expect "repo file not turned into a link" test ! -L "$RCOPY/config/kitty/kitty.conf"

    # tracked-but-deleted file, backup permissions
    in_world
    git -C "$RCOPY" add -A >/dev/null 2>&1
    rm "$RCOPY/config/kitty/kitty.conf"
    mkdir -p "$TGT/hypr"
    printf 'mine\n' >"$TGT/hypr/hyprland.lua"
    run "${IN[@]}" --yes
    expect_rc "a tracked file missing from the working tree is skipped" 0
    expect "backup folder is owner-only" test "$(stat -c %a "$(find "$XDG_STATE_HOME/sumi-files/backups" -mindepth 1 -maxdepth 1 -type d | head -1)")" = 700

    # ── Permissions ──
    in_world
    mkdir -p "$TGT"
    chmod a-w "$TGT"
    run "${IN[@]}" --yes
    expect_rc "read-only target → 77" 77
    chmod u+w "$TGT"
}
