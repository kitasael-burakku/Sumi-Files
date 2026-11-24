# shellcheck shell=bash
# tests/test_privacy.sh — audits every file git would commit. Personal
# strings are never written here: they come from the running user ($USER,
# $HOME) and from the optional, non-versioned
# ~/.config/sumi-files/private-patterns.

test_privacy() {
    echo "privacy audit (files git would commit)"
    local files=() f
    while IFS= read -r -d '' f; do files+=("$f"); done \
        < <(git -C "$ROOT" ls-files -z -co --exclude-standard)
    expect "there are files to audit" test "${#files[@]}" -gt 0

    cd "$ROOT" || return
    OUT="$(grep -nIF -- "$REAL_HOME" "${files[@]}" 2>/dev/null)"
    expect "no literal home path ($REAL_HOME)" test -z "$OUT"
    OUT="$(grep -nIwF -- "$REAL_USER" "${files[@]}" 2>/dev/null)"
    expect "no login name ($REAL_USER)" test -z "$OUT"
    OUT="$(grep -nIoE '/home/[a-z_][a-z0-9_-]*' "${files[@]}" 2>/dev/null | grep -vE ':/home/(user|al|alice|you)$' )"
    expect "no /home/<name>/ paths except examples" test -z "$OUT"
    OUT="$(grep -nIoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "${files[@]}" 2>/dev/null \
        | grep -vE 'with\.rezky@gmail\.com|karl@stavestrand\.no|@example\.(invalid|com|org)|noreply@|@anthropic\.com' \
        | grep -vE ':(git|ssh)@github\.com')"
    expect "no e-mail addresses except third-party credits" test -z "$OUT"
    if [ -f "$REAL_XDG_CONFIG/sumi-files/private-patterns" ]; then
        local list
        list="$(grep -vE '^[[:space:]]*(#|$)' "$REAL_XDG_CONFIG/sumi-files/private-patterns")"
        OUT="$(grep -nIF -f <(printf '%s\n' "$list") "${files[@]}" 2>/dev/null)"
        expect "none of your private-patterns" test -z "$OUT"
    fi
    OUT="$(find "${files[@]}" -size +512k 2>/dev/null)"
    expect "no file over 512 KiB" test -z "$OUT"
    OUT="$(printf '%s\n' "${files[@]}" | grep -iE '\.(png|jpe?g|gif|webp|mp4|mkv|webm|mov)$')"
    expect "no images or videos" test -z "$OUT"
    OUT="$(printf '%s\n' "${files[@]}" | grep -E '(^|/)(private\.lua|local\.fish|fish_variables|\.current-wallpaper)$')"
    expect "no private or state files" test -z "$OUT"
    if command -v gitleaks >/dev/null 2>&1; then
        new_sandbox
        local scan="$SB/scan"
        mkdir -p "$scan"
        (cd "$ROOT" && tar -cf - "${files[@]}") | (cd "$scan" && tar -xf -)
        run gitleaks dir --no-banner --redact -l error "$scan"
        expect_rc "gitleaks finds no secrets" 0
    fi
    cd - >/dev/null || true

    # ── hooks/git/pre-commit in a scratch repository ──
    new_sandbox
    local g="$SB/repo"
    git init -q "$g"
    mkdir -p "$g/hooks"
    cp -r "$ROOT/hooks/git" "$ROOT/hooks/dotbackup" "$g/hooks/"
    git -C "$g" config core.hooksPath hooks/git
    printf 'clean\n' >"$g/ok.txt"
    git -C "$g" add -A
    run git -C "$g" commit -q -m clean
    expect_rc "pre-commit lets a clean commit through" 0
    printf 'path = %s/.config/x\n' "$HOME" >"$g/home.txt"
    git -C "$g" add home.txt
    run git -C "$g" commit -q -m home
    expect "pre-commit blocks a literal home path" test "$RC" != 0
    git -C "$g" rm -q --cached home.txt && rm "$g/home.txt"
    printf 'owner = %s\n' "$SUMI_LOGIN" >"$g/login.txt"
    git -C "$g" add login.txt
    run git -C "$g" commit -q -m login
    expect "pre-commit blocks the login name" test "$RC" != 0
    git -C "$g" rm -q --cached login.txt && rm "$g/login.txt"
    mkdir -p "$g/config/hypr/modules"
    printf 'return {}\n' >"$g/config/hypr/modules/private.lua"
    git -C "$g" add -f config/hypr/modules/private.lua
    run git -C "$g" commit -q -m private
    expect "pre-commit blocks a private file name" test "$RC" != 0
    git -C "$g" rm -q --cached config/hypr/modules/private.lua
    printf 'token = ghp_%s\n' "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8" >"$g/t.txt"
    git -C "$g" add t.txt
    run git -C "$g" commit -q -m token
    expect "pre-commit blocks a token" test "$RC" != 0
    expect "the repository's own clone has the hook enabled" test "$(git -C "$ROOT" config --get core.hooksPath)" = hooks/git
}
