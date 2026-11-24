# shellcheck shell=bash
# tests/test_diskbackup.sh — bin/diskbackup against a temp "disk".

dk_world() {
    new_sandbox
    # The sandbox lives on whatever filesystem TMPDIR is; /proc is never it,
    # so the "system disk" guard is off unless a test turns it on.
    export DISKBACKUP_SYSTEM_PATHS=/proc
    DEST="$SB/backup disk/Backups"
    mkdir -p "$SB/backup disk"
    mkdir -p "$HOME/Projects/my repo" "$HOME/themes/My Theme" "$HOME/Pictures/Wall papers" "$XDG_CONFIG_HOME/hypr/modules"
    git -C "$HOME/Projects/my repo" init -q
    printf 'a\n' >"$HOME/Projects/my repo/a.txt"
    git -C "$HOME/Projects/my repo" add -A
    git -C "$HOME/Projects/my repo" commit -q -m one
    printf 'icon\n' >"$HOME/themes/My Theme/index.theme"
    printf 'img\n' >"$HOME/Pictures/Wall papers/one.png"
    printf 'img2\n' >"$HOME/Pictures/Wall papers/two.png"
    printf 'return {}\n' >"$XDG_CONFIG_HOME/hypr/modules/private.lua"
    printf 'outside\n' >"$HOME/notes.txt"
    mkdir -p "$HOME/snaps"
    printf 'tar\n' >"$HOME/snaps/snapshot-x-1.tar.gz"
    CONF="$XDG_CONFIG_HOME/sumi-files/diskbackup.conf"
    mkdir -p "$(dirname "$CONF")"
    cat >"$CONF" <<EOF
[general]
dest = $DEST
delete = true

[repos]
~/Projects/my repo = my-repo

[themes]
~/themes/My Theme = My-Theme

[files]
~/.config/hypr/modules/private.lua
~/notes.txt

[dirs]
~/Pictures/Wall papers = wallpapers

[state]
echo.txt = echo inventory
broken.txt = exit 3

[snapshots]
from = ~/snaps
EOF
    chmod 600 "$CONF"
}

test_diskbackup() {
    echo "diskbackup"

    # ── CLI ──
    new_sandbox
    run "$DISKBACKUP" --help
    expect_rc "--help exits 0" 0
    run "$DISKBACKUP" --version
    local changelog_version
    changelog_version="$(grep -m1 -oP '^## diskbackup \K[0-9]+\.[0-9]+\.[0-9]+' "$ROOT/CHANGELOG.md")"
    expect "--version matches CHANGELOG ($changelog_version)" test "$OUT" = "diskbackup $changelog_version"
    run "$DISKBACKUP" --nope
    expect_rc "unknown option → 64" 64
    run "$DISKBACKUP" --check --dry-run
    expect_rc "--check with --dry-run → 64" 64
    run "$DISKBACKUP" --only bogus --check
    expect_rc "unknown --only section → 64" 64
    run "$DISKBACKUP" --check
    expect_rc "no settings file → 66 (minimaru: 'not configured')" 66

    # ── Settings validation ──
    dk_world
    chmod 664 "$CONF"
    run "$DISKBACKUP" --check
    expect_rc "group-writable settings → 77" 77
    chmod 600 "$CONF"
    printf '[bogus]\n' >"$SB/bad.conf"
    chmod 600 "$SB/bad.conf"
    run "$DISKBACKUP" --config "$SB/bad.conf" --check
    expect_rc "unknown section → 78" 78
    printf '[general]\ndest = relative/path\n' >"$SB/bad.conf"
    run "$DISKBACKUP" --config "$SB/bad.conf" --check
    expect_rc "relative destination → 65" 65
    run "$DISKBACKUP" --dest / --check
    expect_rc "destination / → 65" 65
    run "$DISKBACKUP" --dest "$HOME" --check
    expect_rc "destination \$HOME → 65" 65
    run "$DISKBACKUP" --dest "$HOME/Pictures/Wall papers/inside" --check
    expect_rc "destination inside a mirrored folder → 65" 65
    printf '[repos]\n~/x = bad/name\n' >"$SB/bad.conf"
    run "$DISKBACKUP" --config "$SB/bad.conf" --check
    expect_rc "name with a slash → 78" 78

    # ── Marker ──
    run "$DISKBACKUP" --check
    expect_rc "destination missing → 1" 1
    mkdir -p "$DEST"
    printf 'keep me\n' >"$DEST/unrelated.txt"
    run "$DISKBACKUP" --yes
    expect_rc "destination without marker → 1" 1
    expect "nothing written without the marker" test "$(ls -A "$DEST")" = "unrelated.txt"
    run "$DISKBACKUP" --init
    expect_rc "--init without --yes off a terminal → 64" 64
    run "$DISKBACKUP" --init --yes
    expect_rc "--init --yes → 0" 0
    expect "marker created" test -f "$DEST/.diskbackup-target"

    # ── Check / dry run / run ──
    local before after
    run "$DISKBACKUP" --check
    expect_rc "--check before the first backup → 2" 2
    expect_out "pending lines keep the '    + ' shape" "    + my-repo"
    before="$(tree_hash "$DEST")"
    run "$DISKBACKUP" --dry-run
    expect_rc "--dry-run → 0" 0
    expect_out "--dry-run describes the clone" "would create"
    after="$(tree_hash "$DEST")"
    expect "--check/--dry-run wrote nothing" test "$before" = "$after"
    run "$DISKBACKUP"
    expect_rc "not a terminal and no --yes → 64" 64
    run "$DISKBACKUP" --yes
    expect_rc "backup → 0 (a failing [state] command only warns)" 0
    expect "bare mirror created" test -f "$DEST/git-mirrors/my-repo.git/HEAD"
    expect "theme mirrored (spaces)" test -f "$DEST/manual-themes/My-Theme/index.theme"
    expect "file under ~/.config keeps its tree" test -f "$DEST/private-files/hypr/modules/private.lua"
    expect "file outside ~/.config goes under _home/" test -f "$DEST/private-files/_home/notes.txt"
    expect "folder mirrored" test -f "$DEST/local-dirs/wallpapers/one.png"
    expect "state file written" grep -qx inventory "$DEST/system-state/echo.txt"
    expect "failed state command leaves no file" test ! -e "$DEST/system-state/broken.txt"
    expect "newest snapshot copied" test -f "$DEST/config-snapshots/snapshot-x-1.tar.gz"
    expect "unrelated file untouched" test -f "$DEST/unrelated.txt"
    run "$DISKBACKUP" --check
    expect_rc "--check right after → 0" 0

    # ── Changes ──
    printf 'b\n' >"$HOME/Projects/my repo/b.txt"
    git -C "$HOME/Projects/my repo" add -A
    git -C "$HOME/Projects/my repo" commit -q -m two
    run "$DISKBACKUP" --check
    expect_rc "new commit → 2" 2
    expect_out "pending lines keep the '    ~ ' shape" "    ~ my-repo"
    rm "$HOME/Pictures/Wall papers/two.png"
    run "$DISKBACKUP" --yes --no-delete --only dirs
    expect "--no-delete keeps the deleted file" test -f "$DEST/local-dirs/wallpapers/two.png"
    run "$DISKBACKUP" --yes --only dirs,repos
    expect "mirror deletes what the source deleted" test ! -e "$DEST/local-dirs/wallpapers/two.png"
    expect "repo mirror updated" test "$(git -C "$DEST/git-mirrors/my-repo.git" log -1 --format=%s)" = two
    printf 'changed\n' >"$HOME/notes.txt"
    run "$DISKBACKUP" --check --only files
    expect_rc "--only files sees the changed file" 2
    run "$DISKBACKUP" --yes --exclude 'notes.txt' --only files
    expect "--exclude skips a loose file" grep -qx outside "$DEST/private-files/_home/notes.txt"

    # ── Mount, permissions, dependencies ──
    run "$DISKBACKUP" --check --require-mount "$SB/backup disk"
    expect_rc "--require-mount on a plain folder → 1" 1
    printf '[general]\ndest = %s\nrequire_mount = %s\n' "$DEST" "$SB/backup disk" >"$SB/m.conf"
    chmod 600 "$SB/m.conf"
    run "$DISKBACKUP" --config "$SB/m.conf" --check --no-require-mount
    expect_rc "--no-require-mount overrides the settings" 0
    chmod a-w "$DEST"
    run "$DISKBACKUP" --yes
    expect_rc "read-only destination → 77" 77
    chmod u+w "$DEST"
    local norsync
    norsync="$(path_without rsync)"
    PATH="$norsync" run "$DISKBACKUP" --check
    expect_rc "rsync missing → 69" 69
    run_input 'n\n' "$DISKBACKUP" --interactive
    expect_rc "answering no → 0" 0

    # ── Audit 2026-11-24: system disk, symlinks, refs, permissions ──
    expect "destination folders are owner-only" test "$(stat -c %a "$DEST/private-files")" = 700
    expect "state folder is owner-only" test "$(stat -c %a "$DEST/system-state")" = 700
    git -C "$HOME/Projects/my repo" branch keep-me
    run "$DISKBACKUP" --yes --only repos
    git -C "$HOME/Projects/my repo" branch -D keep-me >/dev/null
    run "$DISKBACKUP" --yes --only repos
    expect "a branch deleted at the source stays in the mirror" sh -c "git -C '$DEST/git-mirrors/my-repo.git' rev-parse -q --verify refs/heads/keep-me >/dev/null"
    ln -s "$HOME/notes.txt" "$XDG_CONFIG_HOME/linked-note.txt"
    printf '[general]\ndest = %s\n[files]\n~/.config/linked-note.txt\n' "$DEST" >"$SB/l.conf"
    chmod 600 "$SB/l.conf"
    run "$DISKBACKUP" --config "$SB/l.conf" --yes
    expect "a symlinked loose file is stored as content" sh -c "test -f '$DEST/private-files/linked-note.txt' && test ! -L '$DEST/private-files/linked-note.txt'"
    mv "$DEST/local-dirs" "$SB/elsewhere"
    ln -s "$SB/elsewhere" "$DEST/local-dirs"
    run "$DISKBACKUP" --yes --only dirs
    expect_rc "symlinked layout folder → 65" 65
    rm "$DEST/local-dirs"
    mkdir -p "$DEST/local-dirs"
    mkdir -p "$SB/victim"
    printf 'x\n' >"$SB/victim/precious"
    ln -s "$SB/victim" "$DEST/local-dirs/wallpapers"
    run "$DISKBACKUP" --yes --only dirs
    expect_rc "symlinked mirror target → 1" 1
    expect "nothing deleted through the symlink" test -f "$SB/victim/precious"
    rm "$DEST/local-dirs/wallpapers"
    run "$DISKBACKUP" --check --allow-system-disk
    expect_rc "--allow-system-disk without --init → 64" 64

    # The disk "isn't mounted": the destination sits on a system filesystem.
    dk_world
    export DISKBACKUP_SYSTEM_PATHS="$SB"
    run "$DISKBACKUP" --init --yes
    expect_rc "--init on the system disk → 65" 65
    expect "nothing created on the system disk" test ! -e "$DEST"
    mkdir -p "$DEST"
    printf 'diskbackup destination\n' >"$DEST/.diskbackup-target"
    run "$DISKBACKUP" --yes
    expect_rc "run on the system disk with a plain marker → 1" 1
    expect "no layout folder created" test ! -e "$DEST/local-dirs"
    run "$DISKBACKUP" --check
    expect_rc "--check on the system disk → 1 (minimaru: unreachable)" 1
    rm "$DEST/.diskbackup-target"
    run "$DISKBACKUP" --init --yes --allow-system-disk
    expect_rc "--init --allow-system-disk → 0" 0
    run "$DISKBACKUP" --yes --only files
    expect_rc "explicitly allowed system disk → 0" 0
}
