# Configuration

Sumi-Files ships neutral defaults. This page lists what is specific to a
machine or a person, and where to put your own values so they **don't end up
in the repository** the next time you run `dotbackup`.

## Machine-specific values

| File (under `~/.config/`) | Value | Default |
|---|---|---|
| `hypr/modules/monitors.lua` | `mode`, `position`, `scale` | `highrr` (highest refresh rate), all outputs. Pin `"WxH@Hz"` if you need a specific mode |
| `hypr/modules/input.lua` | keyboard layout, pointer acceleration; per-device blocks | `us,es`, Alt+Shift switches, `flat` acceleration. Device examples are commented out — use the slugs from `hyprctl devices` (or put them in `private.lua`) |
| `hypr/modules/environment.lua` | `CursorTheme`, `CursorSize`, `GTKTheme` | `Bibata-Modern-Classic`, 16, `Adwaita-dark` |
| `hypr/modules/environment.lua` | VA-API/VDPAU driver | commented out; set it for your GPU in `private.lua` ([below](#machine-specific-calls-in-privatelua)) |
| `hypr/modules/environment.lua` | `HostnamePretty` | `$HOSTNAME_PRETTY`, else `/etc/hostname`; override in `private.lua` or `local.fish` |
| `hypr/modules/programs.lua` | terminal, file manager, browser | `kitty`, `nautilus`, `zen-browser` |
| `hypr/websites.conf`, `sumi-shell/websites.conf` | web hub bookmarks | generic developer links |
| `fish/config.fish` | fastfetch preset weights | text-logo presets; image presets need logos (`fastfetch/fastfetchlogo/README.md`) |
| `sumi-shell/settings.json` | weather location, lock avatar, monitors | empty / disabled |

`minimaru doctor --fresh-clone` reports which of these don't resolve on your
machine (missing devices, unsupported monitor mode, missing themes…).

## Personal values: keep them out of git

The repository is a mirror of your live config, so any personal value you
type into a versioned file is published on the next `dotbackup --commit`.
Put them in the files Sumi-Files never versions:

| Value | Where |
|---|---|
| Extra programs, autostart commands, private keybinds | `hypr/modules/private.lua` (template: `private.example.lua`) |
| Input devices, GPU driver variables, hostname | top-level calls in `hypr/modules/private.lua` ([below](#machine-specific-calls-in-privatelua)) |
| Aliases, `USER_PRETTY`, `HOSTNAME_PRETTY` | `fish/conf.d/local.fish` |
| Default wallpaper | `SUMI_DEFAULT_WALLPAPER` (e.g. `set -Ux` in Fish, or the environment) |
| Strings that must never be published | `~/.config/sumi-files/private-patterns` |

Both `private.lua` and `local.fish` are excluded by `.dotbackup-exclude` and
`.gitignore`. Back them up with `diskbackup` (`[files]` section) instead.

`private-patterns` lists fixed, case-sensitive strings — real name, device
slugs, city, user names on other services. While any file git would commit
contains one (or your home path, or your login name as a whole word), the
privacy hook refuses the commit (template: `share/examples/private-patterns`).
It runs from `dotbackup` and from `hooks/git/pre-commit`
(`git config core.hooksPath hooks/git`). It is one layer among several —
`.gitignore`, `.dotbackup-exclude`, `@HOME@` normalisation, the token scan —
not the only one.

A file that has to stay different on one machine as a whole (a multi-monitor
`monitors.lua`, for example) can be kept out of the mirror with `exclude =` in
`dotbackup.conf` instead; [MIGRATING.md § 4](MIGRATING.md#4-keep-the-files-that-must-differ-on-this-machine)
walks through it.

### Machine-specific calls in `private.lua`

Besides the `programs`, `autostart` and `binds` fields it returns,
`private.lua` can make top-level Hyprland calls before its `return`. That is
the place for input devices, the GPU driver variables and the hostname:

```lua
-- ~/.config/hypr/modules/private.lua (never versioned)
hl.device({
    name          = "your-mouse-slug",   -- the slug `hyprctl devices` prints
    sensitivity   = 0,
    accel_profile = "flat",
})
hl.env("LIBVA_DRIVER_NAME", "radeonsi")  -- your GPU's driver
hl.env("VDPAU_DRIVER", "radeonsi")
hl.env("HOSTNAME_PRETTY", "workstation")

return {
    programs  = {},
    autostart = {},
    binds     = function(mainMod) end,
}
```

Why this works: `hyprland.lua` requires `environment.lua` and `input.lua`
before `programs.lua`, and `programs.lua` is the first module that requires
`modules.private`. So the file's top level runs once, after the defaults, and
its `hl.env` calls replace the values `environment.lua` set. `autostart.lua`
and `keybinds.lua` require it again later, but Lua returns the module
already loaded and the calls don't repeat. Every `require` is wrapped in
`pcall`, so a missing `private.lua` is simply skipped.

## Deliberate settings

These look like candidates for tweaking, but they are part of the design:

| Setting | Value | Why |
|---|---|---|
| `misc.session_lock_xray` (`misc.lua`) | `true`, required | Sumi Shell's lock screen animates in and out with it (the lock is opaque while locked). `check-config-drift.sh` (`minimaru doctor`) warns when it isn't `true` |
| VRR (`misc.vrr`, `misc.lua`) | `0`, off | deliberately off; Hyprland's default too, set explicitly so a change of default can't turn it on |
| `general.allow_tearing` (`decoration.lua`) | `false` | tearing is not enabled |
| Active border | one solid colour, `borderangle` off | [THEMING.md § Window border](THEMING.md#window-border) |

## Tool settings

| File | Tool | Template |
|---|---|---|
| `~/.config/sumi-files/dotbackup.conf` | `dotbackup` | `share/examples/dotbackup.conf` |
| `~/.config/sumi-files/diskbackup.conf` | `diskbackup` | `share/examples/diskbackup.conf` |
| `~/.config/sumi-files/private-patterns` | privacy hook | `share/examples/private-patterns` |

These live outside the manifest on purpose: they describe your machine, not
the desktop.

## Environment variables

| Variable | Used by | Meaning |
|---|---|---|
| `SUMI_FILES_DIR` | `dotbackup`, `keybinds` | path of your clone |
| `SUMI_DEFAULT_WALLPAPER` | `apply-wallpaper.sh` | wallpaper used until one is picked |
| `SUMI_PRIVATE_PATTERNS` | privacy hook | alternative patterns file |
| `SUMI_LOGIN` | privacy hook | login name to look for (default: `id -un`) |
| `DISKBACKUP_SYSTEM_PATHS` | `diskbackup` | filesystems that count as the system disk (default: `/ $HOME`) |
| `SUMI_SHELL_DIR` | colour scripts | Sumi Shell location (default `~/.config/quickshell/sumi`) |
| `HOSTNAME_PRETTY`, `USER_PRETTY` | Starship, Fastfetch | display names |
| `NO_COLOR` | the tools | plain output |
