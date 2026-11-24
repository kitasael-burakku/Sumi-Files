# dotbackup

Mirror the paths listed in a manifest from your live configuration
(`~/.config`) into a dotfiles git repository, then — only if you ask —
commit and push.

```
dotbackup [OPTIONS]
```

Version 1.0.0 · Fish · depends on `git`, `rsync` (and `tar` for snapshots).

## Quick reference

```bash
dotbackup --check                 # exit 2 if the repo is behind ~/.config
dotbackup --dry-run               # what would change; writes nothing
dotbackup                         # interactive: sync → review → commit? → push?
dotbackup --yes                   # unattended sync, no commit
dotbackup --yes --commit -M "msg" # unattended sync + commit
dotbackup --yes --commit --push   # … + push
```

## What a run does

1. **Validate** — repository exists and is a git top level; source exists and
   is readable; neither contains the other; the manifest parses; (real runs
   only) the branch is the expected one, the remote matches
   `--expect-remote`, no merge/rebase is in progress, the repository is
   writable.
2. **Stage** — copy every manifest entry, minus excludes, into a private
   temporary folder, and replace your home path with `@HOME@`.
3. **Compare** — list what would be added (`+`), changed (`~`) or deleted (`-`)
   in the repository. `--check` stops here (exit 0 or 2); `--dry-run` stops
   here (exit 0).
4. **Holds** — if `<repo>/.dotbackup-holds` lists a file that differs, stop
   before writing (see [Holds](#holds)).
5. **Confirm** — interactive runs ask *"Copy these changes into the
   repository?"*.
6. **Snapshot** — `tar.gz` of the repository (without `.git`) in the snapshot
   folder, owner-only (`0600`); the oldest beyond `--keep` are deleted.
7. **Apply** — mirror the staged copy into `<repo>/<payload>/`.
8. **Hooks** — run the executables in `hooks/dotbackup/` in order; any
   failure stops the run before committing.
9. **Review** — show `git status`; interactive runs offer the full diff and a
   README edit.
10. **Commit** (only with `--commit` or a "yes") — `git add -A`, token scan
    and home-path check ([below](#secret-and-privacy-scan)), informational
    lint, `git commit`. The personal-data hook already ran in step 8.
11. **Push** (only with `--push` or a "yes").

## Options

| Option | Default | Meaning |
|---|---|---|
| `-s, --source DIR` | `$XDG_CONFIG_HOME` or `~/.config` | live config root |
| `-r, --repo DIR` | see [Finding the repository](#finding-the-repository) | dotfiles repository (top level) |
| `-m, --manifest FILE` | `<repo>/sumi-files.list` | what to mirror |
| `--payload SUBDIR` | `config` | repo folder that mirrors the source |
| `-c, --config FILE` | `~/.config/sumi-files/dotbackup.conf` | settings file |
| `--hooks-dir DIR` | `<repo>/hooks/dotbackup` | hooks |
| `--snapshot-dir DIR` | `$XDG_CACHE_HOME/dotbackup/snapshots` | safety tarballs |
| `--keep N` | `5` | snapshots to keep; `0` = never prune |
| `--no-snapshot` | | skip the tarball |
| `-n, --dry-run` | | preview; writes nothing |
| `--check` | | exit 2 if there is drift, 0 if not; writes nothing |
| `-y, --yes` | | non-interactive (required when stdin isn't a terminal) |
| `-i, --interactive` | | ask even when stdin isn't a terminal (answers read from stdin) |
| `--commit` / `--no-commit` | ask (interactive) / no (otherwise) | commit after syncing |
| `--push` | ask / no | push after committing; needs `--commit` when not interactive |
| `-M, --message TEXT` | `dotfiles: backup <date>` | commit message |
| `-b, --branch NAME` | `main` | required current branch; `''` disables the check |
| `--remote NAME` | `origin` | remote to push to |
| `--expect-remote GLOB` | none | refuse to run unless the remote URL matches |
| `-e, --exclude PATTERN` | | rsync exclude, repeatable ([Excludes](#excludes)) |
| `--no-default-excludes` | | drop `__pycache__/`, `*.pyc`, `*.swp`, `*~` |
| `--no-delete` | | never delete anything from the repository |
| `--no-normalize-home` | | keep literal home paths (not recommended) |
| `--skip-hooks` | | don't run the hooks |
| `-q, --quiet` | | only warnings and errors |
| `--no-color` | | plain output (also `NO_COLOR`) |
| `-h, --help`, `-V, --version` | | |

Command-line options override the settings file, which overrides the defaults.

## Finding the repository

In this order: `--repo`, then `$SUMI_FILES_DIR`, then `repo =` in the settings
file, then the git repository containing the script itself (when it has a
`sumi-files.list`). A symlink in `~/.local/bin` pointing into the clone
therefore needs no configuration; a copy does. When none of them gives a
repository, `dotbackup` exits 64.

The last fallback is the repository the *script* lives in: a `dotbackup`
symlinked into a Sumi-Files clone, with no `repo =`, backs up into that
clone. To use your own repository, always name it.

## Using your own repository

`dotbackup` isn't tied to Sumi-Files: it mirrors whatever a manifest lists
into whatever git repository you name. Two ways to start.

### Option A — a fork of Sumi-Files

Fork Sumi-Files on your git host, then:

```bash
git clone https://github.com/your-user/Sumi-Files.git ~/Projects/Sumi-Files
cd ~/Projects/Sumi-Files
git config core.hooksPath hooks/git   # privacy and token checks on every commit
./install.sh --with-tools             # preview first with --dry-run
dotbackup --check
```

A fork keeps the manifest, `.dotbackup-exclude`, `hooks/` and the tests, so
everything on this page applies unchanged. `--with-tools` *copies* the tools
into `~/.local/bin` and, when no settings file exists yet, writes one with
`repo =` pointing at the clone; symlink them instead
([INSTALLATION.md § 9](INSTALLATION.md#9-optional-the-tools)) if you want the
clone's updates to reach the tools.

Right after installing, `--check` exits 0. The colour files the installer
generates (`kitty/colors/colors.conf`, `hypr/colors.lua`, …) live inside
mirrored folders, but `.dotbackup-exclude` keeps them out of the mirror.

On a machine that already has a configuration of its own, follow
[MIGRATING.md](MIGRATING.md) instead.

### Option B — a new repository

Create an empty repository on your git host (no README, so the first push
isn't rejected), then:

```bash
mkdir -p ~/Projects/my-dotfiles && cd ~/Projects/my-dotfiles
git init -b main
git remote add origin git@github.com:your-user/my-dotfiles.git
$EDITOR sumi-files.list
```

A minimal manifest ([syntax](#manifest)):

```
kitty/
starship.toml
~/.bashrc => shell/bashrc
```

The settings file names the repository (`~/.config/sumi-files/dotbackup.conf`,
[template](../share/examples/dotbackup.conf)):

```ini
repo = ~/Projects/my-dotfiles
branch = main
expect_remote = *github.com*your-user/my-dotfiles*
```

Then preview, and run:

```bash
dotbackup --dry-run   # + config/kitty/…, + config/starship.toml, + config/shell/bashrc
dotbackup             # asks before copying, committing and pushing
```

The mirror lands in `<repo>/config/` (the payload folder). The commit runs
`git add -A`, so the first one also includes `sumi-files.list` and anything
else in the folder; add a `.gitignore` first if you keep other files there.

### Settings you will usually touch

| Setting (`dotbackup.conf`) | Option | Default | Use |
|---|---|---|---|
| `repo` | `--repo` | see [above](#finding-the-repository) | your repository's top level; always set it for your own repository |
| `payload` | `--payload` | `config` | the repository folder that mirrors `~/.config`; must be a subfolder, never the repository root |
| `manifest` | `--manifest` | `<repo>/sumi-files.list` | a manifest stored elsewhere or under another name |
| `branch` | `--branch` | `main` | the only branch `dotbackup` writes on (`master`, …); `''` disables the check |
| `expect_remote` | `--expect-remote` | none | glob the remote URL must match; recommended, it stops a push to the wrong repository |
| manifest line `~/path => dst` | | | a file outside `~/.config`; `dst` is relative to the payload, so `~/.bashrc => shell/bashrc` is stored as `config/shell/bashrc` |

### What it doesn't do

- **Create the repository or the remote.** A missing repository folder or
  manifest exits 66; a folder that isn't a git top level exits 65; no
  repository configured at all exits 64. With `expect_remote` set, a missing
  remote stops the run (exit 1) before anything is written; without it, the
  push fails instead.
- **Handle authentication.** The push is a plain `git push <remote> <branch>`
  with git's own credentials: an SSH key, or a credential helper or token for
  HTTPS. An HTTPS remote without credentials fails; the run exits 1 and the
  commit stays local (the message prints the `git push` to retry). The push
  sets no upstream; run `git push -u origin main` once yourself if you want
  one.
- **Bring the repository's checks.** Some protections are built into the
  script; others are files the repository carries:

| Protection | Comes from | In a repository without Sumi-Files' files |
|---|---|---|
| Token scan of the staged diff (gitleaks or the built-in patterns) | `dotbackup` | always |
| Staged lines containing your literal home path abort the commit | `dotbackup` | always (only a warning with `--no-normalize-home`) |
| Home path stored as `@HOME@` | `dotbackup` | always (unless `normalize_home = false`) |
| Built-in excludes, manifest and symlink safety, branch/remote/merge guards, snapshots | `dotbackup` | always |
| Login name and `private-patterns` strings in any file git would commit | `hooks/dotbackup/10-privacy.sh` | only if the repository has it (or `hooks_dir` points at a copy) |
| `Programs.*` guard, `KEYBINDS.txt`, template parity | `hooks/dotbackup/20-…`, `30-…`, `40-…` | Sumi-Files specific; they skip themselves when their files are missing |
| The same checks on a plain `git commit` | `hooks/git/pre-commit` | only if the repository has it and `core.hooksPath` points at it |
| Repository-owned excludes and holds | `.dotbackup-exclude`, `.dotbackup-holds` | only if present |

For a new repository, copying `hooks/dotbackup/10-privacy.sh` into
`<repo>/hooks/dotbackup/` (keep its licence notice) restores the personal-data
check; see [Hooks](#hooks).

## Settings file

`~/.config/sumi-files/dotbackup.conf` — `key = value` lines, `#` comments.
Parsed, never executed. Keys: `repo`, `source`, `manifest`, `payload`,
`branch`, `remote`, `expect_remote`, `snapshot_dir`, `keep`, `hooks_dir`,
`exclude` (repeatable), `normalize_home` (`true`/`false`),
`default_excludes` (`true`/`false`). Template:
[`share/examples/dotbackup.conf`](../share/examples/dotbackup.conf).
An unknown key is an error (exit 78), so a typo never silently disables a
safety check.

## Manifest

```
dir/                 a whole directory, mirrored
file                 a single file
src => dst           stored under another path (dst relative to the payload)
~/path               a source relative to $HOME instead of the source root
# comment
```

Absolute paths, `..`, a `.git` component, duplicate destinations and a
destination inside another directory entry are rejected (exit 65).

## Symlinks

- Inside a mirrored directory, symlinks are copied **as symlinks** (their
  targets are never followed). A link whose target is an absolute path under
  your home is then refused at commit time by the home-path check.
- A listed single file is copied by content (the link is followed).
- Links that point **into the repository** — what `install.sh --link`
  creates — are recognised: a link to the same payload path *is* the
  repository copy, so it is neither compared nor written; a link to another
  repository path is staged as that file's content. Without this, rsync
  would replace the repository file with a link to itself.
- A listed directory that is itself a symlink into the repository
  (stow-style) is refused (exit 65): it can't be mirrored onto itself.
- A payload path that resolves outside the payload (a symlinked folder in
  the repository) is refused (exit 65), so `rsync --delete` can never write
  outside `<repo>/<payload>/`.

## Excludes

Patterns use rsync syntax and come from three places: the built-in defaults,
`exclude =` / `--exclude`, and the repository's own `.dotbackup-exclude`.

- Without an inner `/` (`*.pyc`, `__pycache__/`) a pattern matches a name
  anywhere.
- With one (`hypr/modules/private.lua`) it is a path relative to the source
  root and applies only to the entry it starts with.

Excluded files are neither copied nor deleted: a file already in the
repository stays as it is.

## Deletions

The repository is a mirror. A file deleted inside a listed directory, a listed
file that no longer exists, and a versioned file in a folder listed file by
file that is no longer in the manifest are all deleted from the repository.
A listed directory that doesn't exist at all is skipped (not emptied).
`--no-delete` disables all of this.

## Holds

`<repo>/.dotbackup-holds` lists payload-relative paths that the repository has
*ahead* of the live config (a change made in the repo and not yet deployed).
If any of them differs from the source, nothing is written: deploy the change
or remove the line. Comments and blank lines are allowed.

## Hooks

Every executable file in the hooks folder runs after the sync, sorted by
name, with `DOTBACKUP_REPO`, `DOTBACKUP_PAYLOAD`, `DOTBACKUP_SOURCE` and
`DOTBACKUP_VERSION` in its environment. A non-zero exit stops the run before
committing (the synced files stay in the working tree). Sumi-Files ships:

| Hook | Blocks? | Checks |
|---|---|---|
| `10-privacy.sh` | yes | no file git would commit contains your home path, your login name (whole word; generic names such as `user` or `root` are skipped) or a string from `~/.config/sumi-files/private-patterns` (case-sensitive) — see [CONFIGURATION.md § Personal values](CONFIGURATION.md#personal-values-keep-them-out-of-git) |
| `20-programs-guard.sh` | yes | every `Programs.<key>` used in `hypr/` is defined in `programs.lua` |
| `30-keybinds-doc.sh` | yes (on error) | regenerates `docs/KEYBINDS.txt` from the public `keybinds.lua` only |
| `40-template-parity.sh` | no | matugen templates and static twins declare the same names |

## Commits made outside dotbackup

`dotbackup --no-commit`, `--yes` without `--commit`, or a manual edit leave
changes for a plain `git commit`, which never runs dotbackup's scans. Enable
the repository's git hook once per clone so every commit gets them:

```bash
git config core.hooksPath hooks/git
```

`hooks/git/pre-commit` runs gitleaks (or the built-in token patterns), then
the privacy hook, and refuses
newly added files whose names are generated or private (`private.lua`,
`colors.conf`, `fish_variables`, …) even if a `.gitignore` rule was removed.

## Secret and privacy scan

Before committing, the staged diff is scanned with `gitleaks` when installed,
or with a built-in list of token patterns (AWS, GitHub, GitLab, OpenAI-style,
Slack, Google API keys, private-key blocks) otherwise. Any hit — or any staged
line still containing your literal home path — aborts the commit and unstages
everything (with `--no-normalize-home` the home-path hit is only a warning).
`shellcheck` and `fish -n` run on staged scripts for information only.

## Interactive and automated use

- On a terminal, `dotbackup` asks before writing, before committing and before
  pushing; every question defaults to **no**.
- Off a terminal (a timer, a script, CI) it refuses to write without `--yes`
  and never commits or pushes without `--commit` / `--push`.
- `--interactive` reads the answers from stdin, one per line, for frontends
  that drive the prompts. Questions are printed on stderr, each ending with a
  newline when stdin isn't a terminal.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | success (with `--check`: up to date) |
| 1 | failure: precondition not met, held file, hook failed, secret found, git error |
| 2 | `--check` only: the repository is behind the source |
| 64 | usage error |
| 65 | invalid data: bad manifest entry, not a git repository, overlapping paths |
| 66 | a path doesn't exist (repository, source, manifest, settings file) |
| 69 | missing dependency |
| 73 | can't create a folder |
| 77 | permission denied |
| 78 | invalid settings file |
| 130 | cancelled (Ctrl-C or end of input) |

## Weekly reminder

`systemd/user/dotbackup-remind.timer` runs `hypr/scripts/dotbackup-remind.sh`,
which calls `dotbackup --check --quiet` and sends a desktop notification on
exit 2. It never syncs anything. It needs `dotbackup` on `$PATH` and a way to
find the repository (a symlink, or `repo =` in the settings file).

## Differences from the original script

`dotbackup` 1.0.0 replaces an earlier single-user script with a fixed
repository, remote and branch; its safeguards carry over, now configurable.
Prompts are in English: a frontend that matched the old prompt text should
use `--yes` and flags, or `--interactive` with the new questions.

The snapshots it keeps can be copied to a second disk by `diskbackup`
([DISKBACKUP.md § Settings file](DISKBACKUP.md#settings-file), `[snapshots]`).
