# diskbackup

Mirror git repositories, folders, loose files, a plain-text inventory of the
system and the newest `dotbackup` snapshot to a second disk — everything that
should be backed up but must not be published.

```
diskbackup [OPTIONS]
```

Version 1.0.0 · Fish · depends on `git`, `rsync` (and `mountpoint` when
`require_mount` is used).

## First use

```bash
mkdir -p ~/.config/sumi-files
cp share/examples/diskbackup.conf ~/.config/sumi-files/
chmod 600 ~/.config/sumi-files/diskbackup.conf
$EDITOR ~/.config/sumi-files/diskbackup.conf     # set dest, list what to back up

diskbackup --init        # create the destination and its marker file
diskbackup --dry-run     # what would be done
diskbackup               # asks, then backs up
diskbackup --check       # later: anything pending?
```

Moving an existing backup or machine over: [MIGRATING.md § 7](MIGRATING.md#7-second-disk).
What `diskbackup` is for: the files [CONFIGURATION.md](CONFIGURATION.md#personal-values-keep-them-out-of-git)
keeps out of git, and the snapshots [`dotbackup`](DOTBACKUP.md) leaves.

## Destination layout

```
<dest>/
├── .diskbackup-target     marker created by --init
├── git-mirrors/<name>.git bare mirrors              [repos]
├── manual-themes/<name>/  rsync mirrors             [themes]
├── private-files/…        loose files               [files]
├── local-dirs/<name>/     rsync mirrors             [dirs]
├── system-state/<file>    command output            [state]
└── config-snapshots/      newest dotbackup tarball  [snapshots]
```

`diskbackup` writes only inside these subfolders and only when the marker
exists, so a wrong `dest` can't mirror over an unrelated folder. Everything it
creates is owner-only (umask `077`). It refuses to write through a symlink
in the destination layout.

### When the backup disk is not mounted

An unmounted disk leaves an empty mount point on the system disk, and
anything written there silently fills it. Three independent guards:

1. without the disk, `<dest>` and its marker aren't there → exit 1;
2. `require_mount` (recommended) → exit 1 unless that path is a mount point
   and `dest` is inside it;
3. `--init` refuses a destination on the same filesystem as `/` or `$HOME`
   (exit 65), and every run refuses such a destination unless its marker was
   created with `--init --allow-system-disk` (exit 1). Initialising by
   mistake while the disk is unplugged therefore can't redirect later runs.

`DISKBACKUP_SYSTEM_PATHS` (space-separated) replaces `/ $HOME` as the list of
system filesystems, for unusual layouts. It also
refuses `/`, `$HOME`, `/home`, `/mnt`, `/media` and similar roots as the
destination itself, and refuses a destination that contains, or is inside,
something it mirrors.

## Settings file

`~/.config/sumi-files/diskbackup.conf` (or `--config FILE`). INI-like; `#` or
`;` starts a comment; paths may start with `~/` or `$HOME/`, nothing else is
expanded. The file is parsed, never sourced. Because `[state]` runs commands
from it, it must be **owned by you and not writable by group or others**
(exit 77 otherwise). Template: [`share/examples/diskbackup.conf`](../share/examples/diskbackup.conf).

| Section | Syntax | Result |
|---|---|---|
| `[general]` | `dest = DIR` | destination (absolute) |
| | `require_mount = DIR` | refuse to run unless `DIR` is a mount point, and `dest` must be inside it |
| | `delete = true\|false` | mirrors delete what the source deleted (default `true`) |
| `[repos]` | `path = name` | `git clone --mirror` once, then `git remote update` (never pruned: a branch deleted at the source stays in the backup); reads the local clone, so it works offline and includes unpushed commits |
| `[themes]`, `[dirs]` | `path = name` | `rsync -a [--delete]` mirror |
| `[files]` | `path` | copied by content (a symlink is followed) with its mode and times; under `~/.config` → same relative tree, elsewhere in `$HOME` → `_home/…`, otherwise `_root/…` |
| `[state]` | `name.txt = command` | `sh -c command` output; written only if the command succeeds |
| `[snapshots]` | `from = DIR`, `glob = PATTERN` | copies the newest matching file (default glob `snapshot-*.tar.gz`); never prunes |

Names may contain letters, digits, `.`, `_` and `-` only.

## Options

| Option | Meaning |
|---|---|
| `-c, --config FILE` | settings file |
| `-d, --dest DIR` | override `dest` |
| `--init` | create the destination and its marker, then exit (asks first; needs `--yes` when stdin isn't a terminal) |
| `--allow-system-disk` | with `--init`: accept a destination on the system disk |
| `--check` | write nothing; exit 2 if anything is pending, 0 if not |
| `-n, --dry-run` | print what would be done; write nothing, run no `[state]` command |
| `-o, --only SECTION` | `repos`, `themes`, `files`, `dirs`, `state`, `snapshots`; repeatable or comma-separated |
| `-e, --exclude PATTERN` | rsync exclude for `[themes]`/`[dirs]`, also matched against `[files]` names; repeatable |
| `--no-delete` | keep in mirrors what the source deleted |
| `--require-mount DIR` / `--no-require-mount` | override `require_mount` |
| `-y, --yes` | don't ask (required when stdin isn't a terminal) |
| `-i, --interactive` | ask even when stdin isn't a terminal |
| `--pause` | wait for Enter before exiting (for a launcher window) |
| `-q, --quiet` | only pending items, warnings and errors |
| `--no-color` | plain output (also `NO_COLOR`) |
| `-h, --help`, `-V, --version` | |

`--check` runs the `[state]` commands to compare their output; `--dry-run`
doesn't run them at all.

## Output contract

`minimaru doctor` (and any script) can rely on:

- exit **0** up to date, **2** something pending, **66** not configured, other
  codes: destination unavailable or an error;
- every pending line starts with four spaces and `+ ` (not backed up yet) or
  `~ ` (differs).

## Automation

```ini
# ~/.config/systemd/user/diskbackup.service
[Service]
Type=oneshot
ExecStart=%h/.local/bin/diskbackup --yes --quiet
```

Pair it with a `.timer` if you want it periodic. Off a terminal, a real run
(and `--init`) requires `--yes`; nothing is ever asked. `--check` and
`--dry-run` don't need it.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | success (with `--check`: nothing pending) |
| 1 | an item failed, or the destination is missing, unmarked or not mounted |
| 2 | `--check` only: something is pending |
| 64 | usage error |
| 65 | invalid data: relative or forbidden destination, overlapping paths |
| 66 | no settings file |
| 69 | missing dependency |
| 73 | can't create a folder |
| 77 | permission denied (destination, or an unsafe settings file) |
| 78 | invalid settings file |
| 130 | cancelled |

A `[state]` command that fails, or a configured path that doesn't exist, is a
warning and doesn't change the exit code.

## Restoring

Everything is plain files:

```bash
git clone ~/backup/git-mirrors/project.git ~/Projects/project
rsync -a ~/backup/local-dirs/wallpapers/ ~/Pictures/Wallpapers/
cp -a ~/backup/private-files/hypr/modules/private.lua ~/.config/hypr/modules/
tar -xzf ~/backup/config-snapshots/snapshot-…tar.gz -C /tmp/restore
```

`system-state/` is a checklist. For example, the repository packages are the
explicit ones minus the foreign (AUR) ones:
`comm -23 pacman-explicit.txt pacman-foreign.txt | sudo pacman -S --needed -`.

## Differences from the original script

`diskbackup` 1.0.0 replaces an earlier single-user script whose lists were
hardcoded; they are now sections of the settings file. The destination
layout and the `--check` 0/2 contract are unchanged, so an existing backup
keeps working once `diskbackup --init` adds the marker.
