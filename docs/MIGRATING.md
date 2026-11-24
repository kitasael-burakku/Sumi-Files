# Migrating an existing machine

This page is for a machine that already has a Hyprland configuration of its
own, perhaps an earlier version of these dotfiles. It ends with that machine
running Sumi-Files and backed up by `dotbackup` and `diskbackup`, without
losing or publishing anything specific to it. For a fresh machine,
[INSTALLATION.md](INSTALLATION.md) is enough.

The order matters. Personal values move out of the versioned files *before*
the installer replaces those files. The first `dotbackup` runs only *after*
the machine-specific files are excluded, so none of them reaches git.

The commands work in Bash and Fish. They assume the clone is at
`~/Projects/Sumi-Files` (any path works) and use the installer in copy mode.

## 1. Take a local backup

```bash
mkdir -p ~/backups
(umask 077; tar -czf ~/backups/config-before-sumi-files-$(date +%Y%m%d).tar.gz -C ~ .config)
```

Add `.local/bin` after `.config` if it holds older copies of the tools. The
tarball contains private files: it stays owner-only and outside the
repository. To go back: `tar -xzf ~/backups/config-before-sumi-files-<date>.tar.gz -C ~`.

## 2. Move personal values out of the versioned files

Anything that is true only of this machine or of you goes into files
Sumi-Files never versions
([CONFIGURATION.md § Personal values](CONFIGURATION.md#personal-values-keep-them-out-of-git)):

```bash
cp -n ~/Projects/Sumi-Files/config/hypr/modules/private.example.lua ~/.config/hypr/modules/private.lua
mkdir -p ~/.config/sumi-files
cp -n ~/Projects/Sumi-Files/share/examples/private-patterns ~/.config/sumi-files/
```

(`cp -n` keeps a `private.lua` you already have.)

| What | Where |
|---|---|
| Input-device blocks, GPU driver variables, hostname | top-level `hl.device` / `hl.env` calls in `hypr/modules/private.lua` ([how](CONFIGURATION.md#machine-specific-calls-in-privatelua)) |
| Extra programs, autostart commands, private keybinds | the table `private.lua` returns |
| Aliases, `USER_PRETTY`, `HOSTNAME_PRETTY` | `fish/conf.d/local.fish` |
| Strings that must never be published (real name, device slugs, city…) | `~/.config/sumi-files/private-patterns` |

Both `private.lua` and `local.fish` survive the next step: the installer
only writes files the repository ships, and these two are gitignored.

## 3. Install

```bash
cd ~/Projects/Sumi-Files
git config core.hooksPath hooks/git
./install.sh --dry-run
```

Read the list: `~` lines are files that will be replaced. Then:

```bash
./install.sh --skip-colors    # dynamic (matugen) colours are on
./install.sh                  # static palette
```

With dynamic colours on, use `--skip-colors`. Without it, the installer runs
`apply-static-colors.sh`, which overwrites the colour files matugen
generated with the static palette while the dynamic mode stays switched on
([THEMING.md](THEMING.md)).

Every replaced file is moved, not deleted, to
`~/.local/state/sumi-files/backups/<date>/config/…`, where `<date>` is the
time of the run (`YYYYMMDD-HHMMSS`; `ls ~/.local/state/sumi-files/backups/`).

## 4. Keep the files that must differ on this machine

Some files can't become a `private.lua` override, such as a multi-monitor
`hypr/modules/monitors.lua` or a `sumi-shell/settings.json` with your location
and avatar. Bring them back from the installer's backup folder:

```bash
cp -a ~/.local/state/sumi-files/backups/<date>/config/hypr/modules/monitors.lua ~/.config/hypr/modules/
```

Then exclude each one in your private `~/.config/sumi-files/dotbackup.conf`
([template](../share/examples/dotbackup.conf)), one line per file:

```ini
exclude = hypr/modules/monitors.lua
```

What an exclude means ([DOTBACKUP.md § Excludes](DOTBACKUP.md#excludes)):

- `dotbackup` neither copies nor deletes the file: the repository keeps the
  generic version, which is what other machines install.
- `--check` stops reporting it, so changes to it are only backed up by
  `diskbackup` (add it to `[files]`, step 7).
- Running `./install.sh` again replaces it once more (and backs it up); use
  `--only` for the other paths, or recover it again.

## 5. Point the tools at the clone

```bash
mkdir -p ~/.local/bin
ln -sfn ~/Projects/Sumi-Files/bin/dotbackup ~/.local/bin/dotbackup
ln -sfn ~/Projects/Sumi-Files/bin/diskbackup ~/.local/bin/diskbackup
type -a dotbackup diskbackup
```

The first hit of `type -a` must be the link in `~/.local/bin`. An older
version installed as a Fish function (`fish/functions/dotbackup.fish`) or as
a copy earlier in `$PATH` takes precedence: remove it (it is in the step 1
tarball). With a symlink, `dotbackup` finds the clone by itself; if
`dotbackup.conf` has a `repo =` line, it must name this clone.

## 6. First sync

```bash
dotbackup --check     # 0: nothing to do · 2: differences, listed
dotbackup --dry-run   # the same list, with the snapshot and hooks it would run
```

Each `~` line is a file where this machine still differs from the
repository. Move the difference to `private.lua` / `local.fish` (step 2), or
keep the file and exclude it (step 4), then check again. Generated colour
files never appear: `.dotbackup-exclude` keeps them out.

When the list holds only what you want to publish:

```bash
dotbackup --yes                        # sync into the working tree, no commit
git -C ~/Projects/Sumi-Files status
git -C ~/Projects/Sumi-Files diff
```

The hooks run during that sync; if the privacy hook stops it, the files are
synced but nothing is committed. Fix the reported line and run it again.
Commit with `dotbackup --yes --commit` (add `--push` when ready) or with a
plain `git commit`, which runs the same checks through `hooks/git`.

## 7. Second disk

```bash
cp -n ~/Projects/Sumi-Files/share/examples/diskbackup.conf ~/.config/sumi-files/
chmod 600 ~/.config/sumi-files/diskbackup.conf
$EDITOR ~/.config/sumi-files/diskbackup.conf
```

Set `dest` and `require_mount`, and list in `[files]` everything step 2 and
step 4 kept out of git: `private.lua`, `local.fish`, the excluded files and
the settings files in `~/.config/sumi-files/` (one path per line; or that
folder under `[dirs]`). Then, **with the disk mounted**:

```bash
diskbackup --init       # marks the destination; refuses the system disk
diskbackup --dry-run    # what would be written; runs no [state] command
```

For the first real copy, choose:

- `diskbackup --no-delete` when the destination already holds a backup made
  by an earlier script or by hand, with files that no longer exist at the
  source. Those files stay; once you have reviewed them, later runs can be
  exact mirrors.
- `diskbackup` for an exact mirror right away: anything in the mirrored
  folders that the source no longer has is deleted. Git mirrors (`[repos]`)
  are never pruned either way.

`--init` accepts a destination that already holds a backup: the layout is the
same, so it only adds the marker
([DISKBACKUP.md § Destination layout](DISKBACKUP.md#destination-layout)).

## Without a terminal

A real run of `dotbackup`, `diskbackup` or `install.sh` refuses to write when
stdin isn't a terminal unless you pass `--yes`. That covers scripts, timers,
launchers and the `!` shell escape of editors and assistants. `diskbackup
--init` needs it too, and `dotbackup` also needs `--commit` / `--push` to
commit or push. `--check` and `--dry-run` never need it.
