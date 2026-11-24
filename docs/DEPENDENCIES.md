# Dependencies

Package names are for Arch Linux / CachyOS. On CachyOS several "AUR" packages
(`awww`, `matugen`, `mpvpaper`, `cava`, `hyprpicker`, `nwg-look`) are in the
CachyOS repositories; on plain Arch they come from the AUR.

## The tools (`dotbackup`, `diskbackup`, `install.sh`)

| Needed | Package | Used by |
|---|---|---|
| required | `fish` ≥ 3.5 | `dotbackup`, `diskbackup` |
| required | `bash` ≥ 4 | `install.sh`, hooks |
| required | `git`, `rsync` | `dotbackup`, `diskbackup` |
| required | `coreutils` ≥ 8.30, `findutils`, `sed`, `grep`, `tar`, `gzip`, `diffutils` | all (base system) |
| required for `require_mount` | `util-linux` (`mountpoint`) | `diskbackup` |
| recommended | `gitleaks` | `dotbackup` secret scan (a built-in pattern list is used otherwise) |
| optional | `shellcheck` | `dotbackup` informational lint; test suite |
| optional | `lua` (for `luac`) , `python` | test suite |

No other runtime dependency is introduced by the tools.

## Desktop

```bash
sudo pacman -S --needed \
  hyprland hyprlock hypridle xdg-desktop-portal-hyprland \
  kitty fish starship fastfetch \
  pipewire wireplumber pavucontrol playerctl libpulse \
  networkmanager bluez bluez-utils \
  wl-clipboard cliphist grim slurp \
  udiskie polkit-kde-agent libnotify \
  jq imagemagick ffmpeg ffmpegthumbnailer \
  python python-evdev \
  qt5ct qt6ct ttf-iosevkaterm-nerd adwaita-fonts
```

```bash
# CachyOS repositories or AUR
yay -S awww mpvpaper matugen cava hyprpicker nwg-look
```

| Package | Why |
|---|---|
| `awww` / `mpvpaper` | image / video wallpapers (`hypr/scripts/apply-wallpaper.sh`) |
| `matugen` | optional wallpaper-driven colours ([THEMING.md](THEMING.md)) |
| `cliphist`, `wl-clipboard` | clipboard history units |
| `udiskie` | automount unit |
| `python-evdev` | Infinite Desktop input reader |
| `imagemagick`, `ffmpeg`, `ffmpegthumbnailer` | wallpaper thumbnails, video frame for matugen |
| `polkit-kde-agent` | fallback polkit agent (`polkit-agent.service`) |

## Shell conveniences (optional)

Aliases and functions check for these before using them:
`fzf fd bat eza zoxide ripgrep btop lm_sensors pacman-contrib reflector thefuck`,
and an AUR helper (`yay` or `paru`) for the `aur*` aliases.

## Separate projects

- **Sumi Shell** — bar, menus, notifications, lock screen:
  <https://github.com/kitasael-burakku/Sumi-Shell>. Requires Quickshell.
- **hypr-dynamic-cursors** — optional plugin, installed with `hyprpm`
  ([INSTALLATION.md § 8](INSTALLATION.md#8-optional-hyprland-plugin)).

## Themes, icons, cursors, fonts

Not distributed. The configuration names:

| Kind | Name | Set in |
|---|---|---|
| GTK theme | `Adwaita-dark` (ships with GTK) | `hypr/modules/environment.lua` |
| Cursor | `Bibata-Modern-Classic` (`bibata-cursor-theme`) | `hypr/modules/environment.lua`, `sumi-shell/settings.json` |
| Icons | your choice | `gtk-*/settings.ini` (written by `nwg-look`), `qt5ct.conf`, `qt6ct.conf` — keep them equal |
| Font | IosevkaTerm Nerd Font | Kitty, Sumi Shell |

`CursorTheme` must be the theme's **directory name** under
`/usr/share/icons` or `~/.icons` (case-sensitive), not its display name.
