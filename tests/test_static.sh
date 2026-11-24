# shellcheck shell=bash
# tests/test_static.sh — syntax and lint checks over everything shipped.

test_static() {
    echo "static checks"
    local f bad

    for f in "$DOTBACKUP" "$DISKBACKUP"; do
        expect "fish -n $(basename "$f")" fish --no-config -n "$f"
        expect "fish_indent --check $(basename "$f")" fish_indent --check "$f"
    done

    bad=""
    while IFS= read -r -d '' f; do
        fish --no-config -n "$f" 2>/dev/null || bad+="$f"$'\n'
    done < <(find "$ROOT/config" -path '*/matugen/templates' -prune -o -name '*.fish' -print0)
    OUT="$bad"; expect "fish -n on every config/*.fish" test -z "$bad"

    bad=""
    while IFS= read -r -d '' f; do
        bash -n "$f" 2>/dev/null || bad+="$f"$'\n'
    done < <(find "$ROOT" -path "$ROOT/.git" -prune -o -name '*.sh' -print0)
    OUT="$bad"; expect "bash -n on every *.sh" test -z "$bad"

    if command -v shellcheck >/dev/null 2>&1; then
        OUT="$(shellcheck -S warning "$INSTALL" "$ROOT"/hooks/dotbackup/*.sh "$ROOT"/tests/*.sh 2>&1)"
        expect "shellcheck (warning) on install.sh, hooks and tests" test -z "$OUT"
        OUT="$(find "$ROOT/config" -name '*.sh' -print0 | xargs -0 shellcheck -S error 2>&1)"
        expect "shellcheck (error) on config scripts" test -z "$OUT"
    fi

    bad=""
    while IFS= read -r -d '' f; do
        python3 -I -c 'import ast,sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "$f" 2>/dev/null || bad+="$f"$'\n'
    done < <(find "$ROOT/config" -name '*.py' -print0)
    OUT="$bad"; expect "python syntax (ast, no .pyc written)" test -z "$bad"

    if command -v luac >/dev/null 2>&1; then
        bad=""
        while IFS= read -r -d '' f; do
            luac -p -o /dev/null "$f" 2>/dev/null || bad+="$f"$'\n'
        done < <(find "$ROOT/config" -name '*.lua' -print0)
        OUT="$bad"; expect "luac -p on every *.lua" test -z "$bad"
    fi

    OUT="$(python3 -I - "$ROOT/config" <<'PY'
import json, re, sys, tomllib, pathlib
root = pathlib.Path(sys.argv[1])
bad = []
for p in root.rglob("*.json"):
    if "templates" in p.parts: continue
    try: json.loads(p.read_text())
    except Exception as e: bad.append(f"{p}: {e}")
for p in root.rglob("*.jsonc"):
    # drop // and /* */ comments outside strings
    text = re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/',
                  lambda m: m.group(0) if m.group(0).startswith('"') else '', p.read_text(), flags=re.S)
    try: json.loads(re.sub(r',(\s*[}\]])', r'\1', text))
    except Exception as e: bad.append(f"{p}: {e}")
for p in list(root.rglob("*.toml")):
    if "templates" in p.parts: continue
    try: tomllib.loads(p.read_text())
    except Exception as e: bad.append(f"{p}: {e}")
print("\n".join(bad))
PY
)"
    expect "JSON / JSONC / TOML parse" test -z "$OUT"

    bad=""
    local line
    while IFS= read -r line; do
        line="${line%%#*}"; line="${line%"${line##*[![:space:]]}"}"
        [ -n "$line" ] || continue
        line="${line%/}"
        [ -e "$ROOT/config/$line" ] || bad+="$line"$'\n'
    done < "$ROOT/sumi-files.list"
    OUT="$bad"; expect "every manifest entry exists in config/" test -z "$bad"

    local repo_version installer_version changelog_repo
    repo_version="$(cat "$ROOT/VERSION")"
    installer_version="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$INSTALL")"
    changelog_repo="$(awk '/^## Repository/{f=1;next} f && /^## [0-9]+\.[0-9]+\.[0-9]+/{print $2; exit}' "$ROOT/CHANGELOG.md")"
    expect "VERSION = install.sh = CHANGELOG ($repo_version)" test "$repo_version" = "$installer_version" -a "$repo_version" = "$changelog_repo"
    OUT="$(shellcheck -S warning "$ROOT/hooks/git/pre-commit" 2>&1)"
    expect "shellcheck hooks/git/pre-commit" test -z "$OUT"
}
