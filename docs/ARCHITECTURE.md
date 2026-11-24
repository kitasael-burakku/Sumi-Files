# Architecture

## Repository layout

```
Sumi-Files/
├── config/              payload: config/<x> ↔ ~/.config/<x>
├── sumi-files.list      manifest: which paths are managed
├── .dotbackup-exclude   paths inside managed folders that never enter the repo
├── install.sh           repo → ~/.config (optional)
├── bin/                 dotbackup, diskbackup
├── hooks/dotbackup/     checks run by dotbackup after syncing
├── hooks/git/           pre-commit (git config core.hooksPath hooks/git)
├── share/examples/      settings templates for the tools
├── docs/                documentation; KEYBINDS.txt is generated
└── tests/               test suite (tests/run.sh)
```

The payload lives in `config/` rather than at the root so tools, docs and
tests are never mistaken for configuration, and so new top-level folders
don't collide with `~/.config` names.

## One manifest, two directions

[`sumi-files.list`](../sumi-files.list) is the single description of what
Sumi-Files manages. Three things read it:

```
             install.sh                      dotbackup
config/  ───────────────▶  ~/.config  ───────────────▶  config/
                                   dotbackup --check (dotbackup-remind.timer)
```

- A line ending in `/` is a directory (mirrored: deletions propagate).
- Any other line is a single file. In folders listed file by file
  (`systemd/user/`, `gtk-*`, `qt*ct/`), a versioned file that leaves the list
  is removed from the repo by the next `dotbackup`.
- `src => dst` stores a path under another name; `~/path` reads from `$HOME`.

`systemd/`, `gtk-*/` and `qt*ct/` are listed file by file because the same
folders hold machine state (enabled-unit symlinks, GTK bookmarks, Qt window
geometry) and units you might not want public.

## Home-path placeholder

Some programs need an absolute path and can't expand `~` (`qt5ct.conf`,
`qt6ct.conf`). The repository stores `@HOME@` instead:

- `dotbackup` replaces your home path with `@HOME@` in every text file it
  copies into the repository — only as a whole path component, so
  `/home/al` never rewrites `/home/alice`;
- `install.sh` (or one `sed`, when installing by hand) writes it back.

A side effect: user names in paths can't leak through the mirror.
`dotbackup` also refuses to commit staged lines that still contain the
literal home path.

## Session

The compositor starts almost nothing itself. `hypr/modules/autostart.lua`, on
`hyprland.start`:

1. exports the Wayland environment to the D-Bus/systemd activation
   environment and starts `hyprland-session.service`, which binds to
   `graphical-session.target`;
2. sets the cursor, runs `hyprpm reload -n` and `link-steam-icons.sh`;
3. runs the optional autostart list from `private.lua`.

Every long-running program is a `systemd --user` unit `WantedBy`
`graphical-session.target` (wallpaper daemon, idle daemon, clipboard
watchers, automounter, Infinite Desktop…) with its own restart policy and
journal. On `hyprland.shutdown` the target is stopped and the units with it.
Timers handle periodic jobs: update check, thumbnail refresh, health
notification, and the optional `dotbackup` reminder.

## Hyprland configuration

`hypr/hyprland.lua` uses Hyprland's Lua API (`hl.*`) and requires the modules
in `hypr/modules/` in order — `programs.lua` before `keybinds.lua`, because
keybinds read the global `Programs` table — then the plugin files in
`hypr/plugins/`, each guarded so a missing plugin doesn't abort the config.
`private.lua` is optional and loaded with `pcall` everywhere. `programs.lua`
requires it first, after `environment.lua` and `input.lua`, so its top-level
`hl.device`/`hl.env` calls override those defaults
([CONFIGURATION.md](CONFIGURATION.md#machine-specific-calls-in-privatelua)).

At runtime, Lua-driven settings are re-applied with `hyprctl eval '<lua>'`;
`hypr/infinite_desktop/hypr_ipc.py` is the shared IPC layer for scripts.

## Scripts

| Script (`hypr/scripts/`) | Role |
|---|---|
| `apply-wallpaper.sh` | the only wallpaper entry point (images via awww, videos via mpvpaper); persists the choice and the lock-screen copy |
| `apply-static-colors.sh` | writes every colour file from the static palette (first install, and when dynamic colours are turned off) |
| `matugen_reload.sh`, `matugen_toggle.sh` | dynamic colours ([THEMING.md](THEMING.md)) |
| `generate-keybinds-doc.sh` | renders `KEYBINDS.txt` from `keybinds.lua` |
| `check-template-parity.sh`, `check-config-drift.sh`, `check-personal-paths.sh` | read-only checks behind `minimaru doctor` |
| `dotbackup-remind.sh` | weekly notification when `dotbackup --check` reports drift |
| `lock.sh` | locks through Sumi Shell, falling back to Hyprlock |

`fish/functions/minimaru.fish` is a single CLI over the maintenance functions
(`minimaru health`, `clean`, `update`, `doctor`, `diskbackup`, …).

## The tools

`dotbackup` and `diskbackup` are standalone Fish scripts: each can be copied
anywhere and run alone. They share conventions (option names, exit codes,
settings-file format, `--check`/`--dry-run` semantics) but no code, so
neither depends on the other being installed. They run with
`fish --no-config`: user aliases (`ls → eza`, `grep → ugrep`) and functions
never change their behaviour.

Both stage their work before writing: `dotbackup` copies the selected paths
into a private temporary folder, normalises them and compares that with the
repository; `--check`, `--dry-run` and the real run all start from the same
staged copy, which is why a dry run is an exact preview.
