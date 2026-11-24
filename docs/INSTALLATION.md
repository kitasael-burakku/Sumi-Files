# Installation

Two supported paths that end in the same state:

- **[The installer](#installer)** — `install.sh` copies (or links) everything
  the manifest lists and moves whatever it replaces into a backup folder.
- **[Manual installation](#manual-installation)** — you copy what you want,
  step by step. Nothing in Sumi-Files depends on the installer having run.

Before either: install the packages in [DEPENDENCIES.md](DEPENDENCIES.md) and
skim [CONFIGURATION.md](CONFIGURATION.md) — a few values (monitor, input
devices, GPU driver) are machine-specific. If the machine already has a
configuration you want to keep parts of, follow [MIGRATING.md](MIGRATING.md)
instead.

```bash
git clone https://github.com/kitasael-burakku/Sumi-Files.git ~/Projects/Sumi-Files
cd ~/Projects/Sumi-Files
```

The clone location is free; `~/Projects/Sumi-Files` is only the example used
throughout these docs. If you will commit to your clone (for example with
`dotbackup`), enable its privacy and secret checks once:
`git config core.hooksPath hooks/git`.

---

## Installer

```bash
./install.sh --dry-run        # list what would be added (+) and replaced (~)
./install.sh                  # same list, then asks
```

What it does, in order:

1. Reads [`sumi-files.list`](../sumi-files.list) and collects the files the
   repository ships (in a git clone: tracked or not-ignored files only, so
   private or generated files in a working tree never reach another machine).
2. Compares each with what is already in `~/.config`: identical files are
   skipped, different ones are **moved** to
   `~/.local/state/sumi-files/backups/<date>/` before the new file is written.
   Nothing in `~/.config` is ever deleted.
3. Renders the `@HOME@` placeholder to your home path (see
   [ARCHITECTURE.md § Home-path placeholder](ARCHITECTURE.md#home-path-placeholder)).
4. Runs `hypr/scripts/apply-static-colors.sh` to generate the colour files
   (skip with `--skip-colors`).

Useful options (full list: `./install.sh --help`):

| Option | Effect |
|---|---|
| `-n, --dry-run` | Show the plan, change nothing |
| `-o, --only PATH` | Only one entry, e.g. `--only kitty --only fish` |
| `-l, --link` | Symlink into the clone instead of copying (edits in `~/.config` then land in the repo directly; files with `@HOME@` are still copied). A path in `~/.config` that already resolves into the clone is left alone |
| `-t, --target DIR` | Install somewhere else (useful to inspect the result) |
| `--with-tools` | Also install `dotbackup` and `diskbackup` into `~/.local/bin` (`--bin-dir` to change it). They are copied (symlinked with `--link`); a copy gets `repo =` in `~/.config/sumi-files/dotbackup.conf` when that file doesn't exist yet |
| `--enable-services` | Enable the `systemd --user` units afterwards (see [step 6](#6-enable-the-session-units)) |
| `--skip-colors` | Don't run `apply-static-colors.sh` (keeps the colour files you have, e.g. with dynamic colours on) |
| `-y, --yes` | No questions (required when stdin is not a terminal) |
| `-b, --backup-dir DIR` | Where replaced files go |
| `--no-backup --force` | Replace without keeping copies (not recommended) |

The installer never uses `sudo`, never installs packages and never touches the
system-level parts ([step 7](#7-optional-infinite-desktop-input-reader),
[step 8](#8-optional-hyprland-plugin)) — those stay manual on purpose.

**Undo:** the backup folder mirrors `~/.config`; copy it back:

```bash
cp -a ~/.local/state/sumi-files/backups/<date>/config/. ~/.config/
```

Then continue at [After installing](#after-installing).

---

## Manual installation

### 1. Back up what you have

```bash
cp -a ~/.config ~/.config.before-sumi-files
```

### 2. Copy the configuration

Copy the folders you want from `config/` into `~/.config/`. The full set is
what [`sumi-files.list`](../sumi-files.list) lists:

```bash
cd ~/Projects/Sumi-Files/config
cp -r cava fastfetch fish hypr hyprlock kitty matugen sumi-shell ~/.config/
cp starship.static.toml ~/.config/
mkdir -p ~/.config/systemd/user ~/.config/gtk-3.0 ~/.config/gtk-4.0 \
         ~/.config/qt5ct/colors ~/.config/qt6ct/colors
cp systemd/user/* ~/.config/systemd/user/
cp gtk-3.0/* ~/.config/gtk-3.0/
cp gtk-4.0/* ~/.config/gtk-4.0/
cp qt5ct/qt5ct.conf ~/.config/qt5ct/ && cp qt5ct/colors/* ~/.config/qt5ct/colors/
cp qt6ct/qt6ct.conf ~/.config/qt6ct/ && cp qt6ct/colors/* ~/.config/qt6ct/colors/
```

`cp -r` keeps the executable bits git checked out. If a script refuses to run
later: `chmod +x ~/.config/hypr/scripts/*.sh ~/.config/hyprlock/scripts/*.sh`.

### 3. Replace the `@HOME@` placeholder

Two files store an absolute path that the program can't expand itself:

```bash
sed -i "s|@HOME@|$HOME|g" ~/.config/qt5ct/qt5ct.conf ~/.config/qt6ct/qt6ct.conf
grep -rl '@HOME@' ~/.config     # should print nothing
```

### 4. Generate the colour files

The per-app colour files are generated, not versioned. Create them from the
static palette **before the first login**:

```bash
~/.config/hypr/scripts/apply-static-colors.sh
```

### 5. Adapt the machine-specific values

See [CONFIGURATION.md](CONFIGURATION.md). At minimum: `hypr/modules/monitors.lua`
if `mode = "highrr"` (highest refresh rate) doesn't pick the mode you want or
you need a position or scale, the GPU driver variables (in `private.lua`,
[CONFIGURATION.md § Machine-specific calls](CONFIGURATION.md#machine-specific-calls-in-privatelua)),
and `hypr/modules/programs.lua` if you use other apps.

### 6. Enable the session units

The session is a set of `systemd --user` units bound to
`graphical-session.target` (see [ARCHITECTURE.md § Session](ARCHITECTURE.md#session)).
Copying them is not enough; enable them:

```bash
systemctl --user daemon-reload
systemctl --user enable \
    hypridle.service awww.service wallpaper.service \
    cliphist-text.service cliphist-image.service udiskie.service \
    infinite-desktop.service \
    updates-check.timer thumbs-refresh.timer healthcheck-notify.timer
```

- `hyprland-session.service` is not enabled: Hyprland starts it on login.
- `polkit-agent.service` stays disabled when Sumi Shell provides the polkit
  agent; enable it if you run without the shell.
- `dotbackup-remind.timer` only makes sense once `dotbackup` is installed
  (see [DOTBACKUP.md § Weekly reminder](DOTBACKUP.md#weekly-reminder)).

`./install.sh --enable-services` enables this list, plus
`dotbackup-remind.timer` when `dotbackup` is on `$PATH` or in `--bin-dir`.

### 7. (Optional) Infinite Desktop input reader

The Infinite Desktop reads Super/Alt/Ctrl and mouse motion through a small
root-owned socket service, so your user doesn't need to be in the `input`
group. Review `config/hypr/infinite_desktop/system/install.sh`, then:

```bash
pkexec bash ~/.config/hypr/infinite_desktop/system/install.sh
# undo: pkexec bash ~/.config/hypr/infinite_desktop/system/uninstall.sh
```

### 8. (Optional) Hyprland plugin

`hypr/plugins/dym-cursor.lua` configures
[hypr-dynamic-cursors](https://github.com/VirtCode/hypr-dynamic-cursors). The
file returns early when the plugin isn't loaded, so this step can be skipped.

```bash
hyprpm update
hyprpm add https://github.com/virtcode/hypr-dynamic-cursors
hyprpm enable dynamic-cursors
```

`autostart.lua` runs `hyprpm reload -n` on every login. After each Hyprland
update run `hyprpm update` yourself (it needs `sudo`, so it is never automatic).

### 9. (Optional) The tools

```bash
mkdir -p ~/.local/bin
ln -s ~/Projects/Sumi-Files/bin/dotbackup ~/.local/bin/dotbackup
ln -s ~/Projects/Sumi-Files/bin/diskbackup ~/.local/bin/diskbackup
```

A symlink lets `dotbackup` find the repository by itself; a copy needs
`repo =` in `~/.config/sumi-files/dotbackup.conf`. Manuals:
[DOTBACKUP.md](DOTBACKUP.md) (including
[backing up into your own repository](DOTBACKUP.md#using-your-own-repository))
and [DISKBACKUP.md](DISKBACKUP.md).

---

## After installing

1. **Fish as login shell** (optional): `chsh -s /usr/bin/fish`.
2. **Sumi Shell**: install it from its own repository; it provides the bar,
   menus, notifications and the lock screen. Without it, Hyprlock locks the
   session (`hypr/scripts/lock.sh` falls back automatically).
3. **Wallpaper**: pick one from Sumi Shell, or run
   `~/.config/hypr/scripts/apply-wallpaper.sh /path/to/image.png`.
   Set `SUMI_DEFAULT_WALLPAPER` to have a fallback on first login.
4. Log out and select Hyprland.
5. Check the result: `minimaru doctor` (read-only checks of the colour files,
   cross-file wiring and the keybind reference) and
   `minimaru doctor --fresh-clone` (machine-specific values that don't resolve
   on your machine yet).

## Troubleshooting

| Symptom | Cause |
|---|---|
| Qt apps ignore the palette | `@HOME@` still in `qt5ct.conf`/`qt6ct.conf` (step 3) |
| Terminal, lock screen or GTK apps unthemed | colour files not generated (step 4) |
| A unit is `disabled` after copying | units need `systemctl --user enable` (step 6) |
| Keyboard/mouse settings ignored | device names in `input.lua` must be the slugs from `hyprctl devices` |
| No wallpaper on first login | nothing chosen yet and `SUMI_DEFAULT_WALLPAPER` unset — expected |
| Cursor plugin not loading after an update | run `hyprpm update` (step 8) |

## Uninstalling

Sumi-Files has no system-wide footprint unless you ran steps 7–8. Disable the
units (`systemctl --user disable …`), then restore your backup
(`~/.config.before-sumi-files` or the installer's backup folder). Remove the
input reader with its `uninstall.sh`, the plugin with `hyprpm remove`.
