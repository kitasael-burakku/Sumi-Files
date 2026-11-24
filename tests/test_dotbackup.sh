# shellcheck shell=bash
# tests/test_dotbackup.sh — bin/dotbackup in isolated sandboxes.

# A tiny dotfiles world: a live config with spaces in its paths, a repo with
# a manifest, and a bare repository standing in for the remote.
db_world() {
    new_sandbox
    # Not $XDG_CONFIG_HOME: fish itself may write there, which would muddy
    # the "nothing was written" checks.
    SRC="$SB/live config"
    REPO="$SB/my dotfiles"
    REMOTE="$SB/remote.git"
    mkdir -p "$SRC/app/nested dir" "$SRC/sub" "$SRC/notlisted"
    printf 'theme = dark\n' >"$SRC/app/main.conf"
    printf 'path = %s/.config/app\nother = %s2/x\n' "$HOME" "$HOME" >"$SRC/app/nested dir/with home.conf"
    printf 'cache\n' >"$SRC/app/junk.pyc"
    printf 'one\n' >"$SRC/sub/one.conf"
    printf 'single\n' >"$SRC/single.conf"
    printf 'extra\n' >"$HOME/extra.txt"
    git init -q --bare "$REMOTE"
    git init -q "$REPO"
    git -C "$REPO" remote add origin "$REMOTE"
    cat >"$REPO/sumi-files.list" <<'EOF'
# test manifest
app/
single.conf
sub/one.conf
~/extra.txt => extra/extra.txt
EOF
    printf '# test\n' >"$REPO/README.md"
    git -C "$REPO" add -A
    git -C "$REPO" commit -q -m init
    git -C "$REPO" push -q origin main 2>/dev/null
    DB=("$DOTBACKUP" --repo "$REPO" --source "$SRC")
}

test_dotbackup() {
    echo "dotbackup"

    # ── CLI ──
    new_sandbox
    run "$DOTBACKUP" --help
    expect_rc "--help exits 0" 0
    expect_out "--help documents --dry-run" "--dry-run"
    run "$DOTBACKUP" --version
    expect_rc "--version exits 0" 0
    local changelog_version
    changelog_version="$(grep -m1 -oP '^## dotbackup \K[0-9]+\.[0-9]+\.[0-9]+' "$ROOT/CHANGELOG.md")"
    expect "--version matches CHANGELOG ($changelog_version)" test "$OUT" = "dotbackup $changelog_version"
    run "$DOTBACKUP" --bogus
    expect_rc "unknown option → 64" 64
    run "$DOTBACKUP" extra-arg
    expect_rc "positional argument → 64" 64
    run "$DOTBACKUP" --yes --interactive
    expect_rc "--yes with --interactive → 64" 64
    run "$DOTBACKUP" --check --commit
    expect_rc "--check with --commit → 64" 64
    run "$DOTBACKUP" --keep abc
    expect_rc "--keep abc → 64" 64
    run "$DOTBACKUP" --push --no-commit
    expect_rc "--push with --no-commit → 64" 64

    # ── Finding the repository ──
    new_sandbox
    mkdir -p "$SB/loose"
    cp "$DOTBACKUP" "$SB/loose/dotbackup"
    run "$SB/loose/dotbackup" --check
    expect_rc "copied script with no repo configured → 64" 64
    db_world
    mkdir -p "$XDG_CONFIG_HOME/sumi-files"
    printf 'repo = %s\n' "$REPO" >"$XDG_CONFIG_HOME/sumi-files/dotbackup.conf"
    cp "$DOTBACKUP" "$SB/dotbackup-copy"
    run "$SB/dotbackup-copy" --check --source "$SRC"
    expect_rc "repo from the settings file (with spaces) → 2 (drift)" 2
    touch "$SB/empty.conf"
    SUMI_FILES_DIR="$REPO" run "$SB/dotbackup-copy" --check --source "$SRC" --config "$SB/empty.conf"
    expect_rc "repo from SUMI_FILES_DIR → 2" 2

    # ── Validation ──
    db_world
    run "$DOTBACKUP" --repo "$SB/nope" --source "$SRC" --check
    expect_rc "missing repository → 66" 66
    mkdir -p "$SB/plain"
    run "$DOTBACKUP" --repo "$SB/plain" --source "$SRC" --check
    expect_rc "folder that isn't a git repo → 65" 65
    run "$DOTBACKUP" --repo "$REPO" --source "$SB/nope" --check
    expect_rc "missing source → 66" 66
    run "$DOTBACKUP" --repo "$REPO" --source "$REPO/.." --check
    expect_rc "source containing the repo → 65" 65
    run "${DB[@]}" --manifest "$SB/nope.list" --check
    expect_rc "missing manifest → 66" 66
    printf '../escape/\n' >"$SB/bad.list"
    run "${DB[@]}" --manifest "$SB/bad.list" --check
    expect_rc "manifest entry with .. → 65" 65
    printf '/etc/passwd\n' >"$SB/bad.list"
    run "${DB[@]}" --manifest "$SB/bad.list" --check
    expect_rc "absolute manifest entry → 65" 65
    printf 'colour = blue\n' >"$SB/bad.conf"
    run "${DB[@]}" --config "$SB/bad.conf" --check
    expect_rc "unknown settings key → 78" 78
    run "${DB[@]}" --config "$SB/missing.conf" --check
    expect_rc "missing --config file → 66" 66
    run "${DB[@]}"
    expect_rc "not a terminal and no --yes → 64" 64

    # ── --check and --dry-run write nothing ──
    db_world
    local before_src before_repo after_src after_repo
    before_src="$(tree_hash "$SRC" "$HOME/extra.txt")"
    before_repo="$(tree_hash "$REPO")"
    run "${DB[@]}" --check
    expect_rc "--check on an outdated repo → 2" 2
    expect_out "--check lists a new file" "+ config/app/main.conf"
    run "${DB[@]}" --dry-run
    expect_rc "--dry-run → 0" 0
    expect_out "--dry-run says nothing was written" "nothing was written"
    after_src="$(tree_hash "$SRC" "$HOME/extra.txt")"
    after_repo="$(tree_hash "$REPO")"
    expect "--check/--dry-run left the source untouched" test "$before_src" = "$after_src"
    expect "--check/--dry-run left the repo untouched" test "$before_repo" = "$after_repo"
    expect "--dry-run created no snapshot" test ! -e "$XDG_CACHE_HOME/dotbackup"

    # ── Sync ──
    run "${DB[@]}" --yes
    expect_rc "--yes sync → 0" 0
    expect "dir entry synced" test -f "$REPO/config/app/main.conf"
    expect "path with spaces synced" test -f "$REPO/config/app/nested dir/with home.conf"
    expect "home-relative entry mapped to its dst" test -f "$REPO/config/extra/extra.txt"
    expect "default exclude kept *.pyc out" test ! -e "$REPO/config/app/junk.pyc"
    expect "unlisted folder not copied" test ! -e "$REPO/config/notlisted"
    expect "home path normalised to @HOME@" grep -qF 'path = @HOME@/.config/app' "$REPO/config/app/nested dir/with home.conf"
    expect "a longer path sharing the prefix is left alone" grep -qF "other = $HOME""2/x" "$REPO/config/app/nested dir/with home.conf"
    expect "source still has the literal path" grep -qF "path = $HOME/.config/app" "$SRC/app/nested dir/with home.conf"
    expect "snapshot created" test "$(find "$XDG_CACHE_HOME/dotbackup/snapshots" -name 'snapshot-my dotfiles-*.tar.gz' | wc -l)" = 1
    expect "snapshot excludes .git" sh -c "! tar -tzf \"\$(find '$XDG_CACHE_HOME/dotbackup/snapshots' -name '*.tar.gz' | head -1)\" | grep -q '/\.git/'"
    expect "--yes without --commit didn't commit" test "$(git -C "$REPO" rev-list --count HEAD)" = 1
    run "${DB[@]}" --check
    expect_rc "--check after sync → 0" 0

    # ── Commit and push only with flags ──
    run "${DB[@]}" --yes --commit --message "test backup"
    expect_rc "--yes --commit → 0" 0
    expect "commit created with the message" test "$(git -C "$REPO" log -1 --format=%s)" = "test backup"
    expect "not pushed without --push" test "$(git -C "$REMOTE" rev-list --count main)" = 1
    printf 'theme = light\n' >"$SRC/app/main.conf"
    run "${DB[@]}" --yes --commit --push --message "second"
    expect_rc "--yes --commit --push → 0" 0
    expect "remote received the commit" test "$(git -C "$REMOTE" log -1 --format=%s main)" = "second"
    run "${DB[@]}" --yes --push
    expect_rc "--push without --commit when not interactive → 64" 64

    # ── Mirror deletions ──
    rm "$SRC/app/main.conf" "$SRC/single.conf"
    run "${DB[@]}" --check
    expect_out "--check reports a deletion in a dir entry" "- config/app/main.conf"
    expect_out "--check reports a deleted single file" "- config/single.conf"
    run "${DB[@]}" --yes --no-delete
    expect "--no-delete keeps the repo copy" test -f "$REPO/config/app/main.conf"
    run "${DB[@]}" --yes
    expect "a file deleted at the source is deleted in the repo" test ! -e "$REPO/config/app/main.conf"
    expect "a missing single file is deleted in the repo" test ! -e "$REPO/config/single.conf"
    git -C "$REPO" add -A && git -C "$REPO" commit -q -m sync
    printf 'two\n' >"$REPO/config/sub/two.conf"
    git -C "$REPO" add -A && git -C "$REPO" commit -q -m "tracked, unlisted"
    run "${DB[@]}" --yes
    expect "tracked file no longer in the manifest is removed" test ! -e "$REPO/config/sub/two.conf"
    git -C "$REPO" add -A && git -C "$REPO" commit -q -m sync2

    # ── Excludes ──
    printf 'tmp\n' >"$SRC/app/scratch.tmp"
    printf 'private\n' >"$SRC/app/private.lua"
    printf 'app/private.lua\n' >"$REPO/.dotbackup-exclude"
    run "${DB[@]}" --yes --exclude '*.tmp'
    expect "--exclude pattern honoured" test ! -e "$REPO/config/app/scratch.tmp"
    expect "path-scoped .dotbackup-exclude honoured" test ! -e "$REPO/config/app/private.lua"
    git -C "$REPO" add -A && git -C "$REPO" commit -q -m excl

    # ── Secret scan blocks the commit ──
    printf 'token = ghp_%s\n' "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8" >"$SRC/app/leak.conf"
    local head_before
    head_before="$(git -C "$REPO" rev-parse HEAD)"
    run "${DB[@]}" --yes --commit --message leak
    expect_rc "planted token → commit refused (1)" 1
    expect "no commit was made" test "$(git -C "$REPO" rev-parse HEAD)" = "$head_before"
    expect "index left clean after the refusal" test -z "$(git -C "$REPO" diff --cached --name-only)"
    local nogl
    nogl="$(path_without gitleaks)"
    PATH="$nogl" run "${DB[@]}" --yes --commit --message leak
    expect_rc "built-in patterns (no gitleaks) also refuse → 1" 1
    rm "$SRC/app/leak.conf"
    run "${DB[@]}" --yes
    git -C "$REPO" add -A && git -C "$REPO" commit -q -m clean

    # ── Privacy hook from the real repository ──
    mkdir -p "$REPO/hooks/dotbackup"
    cp "$ROOT/hooks/dotbackup/10-privacy.sh" "$REPO/hooks/dotbackup/"
    printf 'my-secret-device\n' >"$SB/patterns"
    printf 'mouse = my-secret-device\n' >"$SRC/app/input.conf"
    SUMI_PRIVATE_PATTERNS="$SB/patterns" run "${DB[@]}" --yes --commit --message private
    expect_rc "private pattern → hook blocks (1)" 1
    expect_out "hook names the file" "input.conf"
    rm "$SRC/app/input.conf"
    SUMI_PRIVATE_PATTERNS="$SB/patterns" run "${DB[@]}" --yes --commit --message "hooks ok"
    expect_rc "clean tree passes the privacy hook" 0
    run "${DB[@]}" --yes --skip-hooks
    expect_rc "--skip-hooks runs" 0

    # ── Preconditions ──
    git -C "$REPO" checkout -q -b other
    printf 'x\n' >"$SRC/single.conf"
    run "${DB[@]}" --yes
    expect_rc "wrong branch → 1" 1
    run "${DB[@]}" --yes --branch ''
    expect_rc "--branch '' disables the check" 0
    git -C "$REPO" checkout -q main 2>/dev/null || { git -C "$REPO" stash -q -u; git -C "$REPO" checkout -q main; }
    run "${DB[@]}" --yes --expect-remote '*github.com*'
    expect_rc "--expect-remote mismatch → 1" 1
    run "${DB[@]}" --yes --expect-remote "*remote.git"
    expect_rc "--expect-remote match → 0" 0
    git -C "$REPO" add -A && git -C "$REPO" commit -q -m pre

    # ── Holds ──
    printf 'repo is ahead\n' >"$REPO/config/sub/one.conf"
    printf 'sub/one.conf\n' >"$REPO/.dotbackup-holds"
    local held_hash
    held_hash="$(tree_hash "$REPO/config")"
    run "${DB[@]}" --yes
    expect_rc "held file differs → 1" 1
    expect "nothing written while held" test "$held_hash" = "$(tree_hash "$REPO/config")"
    rm "$REPO/.dotbackup-holds"
    git -C "$REPO" checkout -q -- config/sub/one.conf

    # ── Interactive answers ──
    printf 'interactive\n' >"$SRC/single.conf"
    local h
    h="$(tree_hash "$REPO/config")"
    run_input 'n\n' "${DB[@]}" --interactive
    expect_rc "answering no → 0" 0
    expect "answering no wrote nothing" test "$h" = "$(tree_hash "$REPO/config")"
    run_input 'y\nn\nn\ny\nfrom stdin\nn\n' "${DB[@]}" --interactive
    expect_rc "interactive sync + commit → 0" 0
    expect "interactive commit message used" test "$(git -C "$REPO" log -1 --format=%s)" = "from stdin"
    run_input 'y\n' "${DB[@]}" --interactive
    expect "end of input while asking → 0 or 130" test "$RC" = 0 -o "$RC" = 130

    # ── Snapshot retention ──
    rm -rf "$XDG_CACHE_HOME/dotbackup/snapshots"
    local i
    for i in 1 2 3 4; do
        printf 'v%s\n' "$i" >"$SRC/single.conf"
        run "${DB[@]}" --yes --keep 2
    done
    expect "--keep 2 keeps two snapshots" test "$(find "$XDG_CACHE_HOME/dotbackup/snapshots" -name '*.tar.gz' | wc -l)" = 2
    printf 'v5\n' >"$SRC/single.conf"
    run "${DB[@]}" --yes --snapshot-dir "$REPO/snaps"
    expect_rc "snapshot dir inside the repo → 65" 65

    # ── Permissions and dependencies ──
    printf 'v6\n' >"$SRC/single.conf"
    chmod a-w "$REPO/config"
    run "${DB[@]}" --yes --no-snapshot
    expect_rc "read-only payload → 77" 77
    chmod u+w "$REPO/config"
    chmod a-r "$SRC/sub/one.conf"
    run "${DB[@]}" --check
    expect_rc "unreadable source file → 77" 77
    chmod u+r "$SRC/sub/one.conf"
    local norsync
    norsync="$(path_without rsync)"
    PATH="$norsync" run "${DB[@]}" --check
    expect_rc "rsync missing → 69" 69

    # ── Audit 2026-11-24: path boundaries ──
    db_world
    run "${DB[@]}" --payload .git --check
    expect_rc "--payload .git → 65" 65
    printf 'app/ => .git/hooks/\n' >"$SB/git.list"
    run "${DB[@]}" --manifest "$SB/git.list" --check
    expect_rc "destination inside a .git component → 65" 65
    printf 'app/\napp/main.conf\n' >"$SB/nested.list"
    run "${DB[@]}" --manifest "$SB/nested.list" --check
    expect_rc "destination nested in a directory entry → 65" 65
    mkdir -p "$SB/outside" "$REPO/config"
    printf 'keep\n' >"$SB/outside/precious"
    ln -s "$SB/outside" "$REPO/config/app"
    run "${DB[@]}" --yes
    expect_rc "payload folder symlinked outside the repo → 65" 65
    expect "nothing written through it" sh -c "test -f '$SB/outside/precious' && test \$(ls -A '$SB/outside' | wc -l) = 1"
    rm "$REPO/config/app"
    ln -s "$REPO/config" "$SB/fake-src"
    run "$DOTBACKUP" --repo "$REPO" --source "$SB/fake-src/.." --check
    expect "a source reached through a link into the repo is refused" test "$RC" = 65

    # Symlinks inside a mirrored directory
    db_world
    ln -s "$HOME/extra.txt" "$SRC/app/abs-link"
    run "${DB[@]}" --yes --commit -M "abs link"
    expect_rc "symlink with a literal home path → commit refused (1)" 1
    expect_out "the home-path check names it" "staged lines contain your home path"
    rm "$SRC/app/abs-link"
    ln -s main.conf "$SRC/app/rel-link"
    run "${DB[@]}" --yes --commit -M "rel link"
    expect_rc "relative symlink is mirrored and committed" 0
    expect "it stays a symlink in the repo" test -L "$REPO/config/app/rel-link"

    # --quiet really is quiet
    printf 'q\n' >>"$SRC/app/main.conf"
    run "${DB[@]}" --yes --quiet
    expect "--quiet prints no change listing" test -z "$(printf '%s' "$OUT" | grep -E '^ +[~+-] |^ +\?\? ')"
    expect "snapshots are owner-only" test "$(stat -c %a "$(find "$XDG_CACHE_HOME/dotbackup/snapshots" -name '*.tar.gz' | head -1)")" = 600
}
