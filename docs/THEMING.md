# Theming

## Two modes

- **Static (default):** the fixed "Minimaru" palette. Every themed program has
  a `*.static.*` file in the repository; `apply-static-colors.sh` copies them
  to the names the programs read.
- **Dynamic (opt-in):** [matugen](https://github.com/InioX/matugen) derives a
  Material You palette from the current wallpaper and renders the templates
  in `matugen/templates/` to the same output names.

The generated files are never versioned (`.gitignore`); only the templates and
their static twins are.

| Template (`matugen/templates/`) | Output | Static twin |
|---|---|---|
| `kitty-colors.conf` | `kitty/colors/colors.conf` | `kitty/colors/colors.static.conf` |
| `hyprlock-colors.conf` | `hyprlock/colors.conf` | `hyprlock/colors.static.conf` |
| `hypr-colors.sh`, `hypr-colors.lua` | `hypr/dynamic-colors.sh`, `hypr/colors.lua` | `hypr/scripts/dynamic-colors.static.sh`, `hypr/colors.static.lua` |
| `starship.toml` | `starship.toml` | `starship.static.toml` |
| `theme-goldship.fish` | `fish/conf.d/theme-goldship.fish` | `fish/theme-goldship.static.fish` |
| `music-progress-colors.sh` | `hyprlock/scripts/music-colors.sh` | `hyprlock/scripts/music-colors.static.sh` |
| `gtk-colors.css` | `gtk-3.0/gtk-colors.css`, `gtk-4.0/gtk-colors.css` | `gtk-*/gtk-colors.static.css` |
| `qt-colors.conf` | `qt5ct/colors/minimaru.conf`, `qt6ct/colors/minimaru.conf` | `qt*ct/colors/minimaru.static.conf` |
| (Sumi Shell's own template) | `~/.local/state/sumi-shell/colors.json` | shipped with Sumi Shell |

A template and its static twin must declare the same identifiers;
`check-template-parity.sh` verifies it (also run by `dotbackup` as an
informational hook).

## Switching

- Dynamic colours are gated by the sentinel file
  `$XDG_STATE_HOME/sumi-shell/theme/enabled` (default
  `~/.local/state/sumi-shell/theme/enabled`). `hypr/scripts/matugen_toggle.sh`
  creates/removes it and regenerates; Sumi Shell's theme surface does the same.
- Next to it, `scheme`, `mode`, `contrast` and `source` hold the matugen
  options (scheme default: `scheme-tonal-spot`; one of the nine matugen
  schemes). They are session state, never versioned.
- Per-application reloads are `post_hook`s in `matugen/config.toml`, each
  bounded with `timeout … || true`: matugen runs hooks in the foreground, so
  one hung hook would stop every template after it.

## Window border

The active border is one solid colour in both modes: the static accent, or
in dynamic mode the wallpaper's primary colour at 80 % alpha. It has no
gradient and no angle. The inactive border is the same colour at about 6 %
alpha. The colour is stored in `hypr/colors.lua`, which
`hypr/modules/decoration.lua` reads at startup and on every reload.
`hypr/dynamic-colors.sh` applies it live with `hyprctl eval`.

The `borderangle` animation is disabled (`hypr/modules/animations.lua`). It
is a looping animation, so it would keep Hyprland redrawing every frame even
when nothing moves, and a solid border has no angle to animate. The `border`
animation (the colour change on focus) stays on.

## GTK

`gtk-3.0/gtk.css` and `gtk-4.0/gtk.css` are one line, `@import 'gtk-colors.css';`.
That file defines both the libadwaita `*_color` names and the GTK 3
`@theme_*` names, so one file themes both toolkits on top of stock
`Adwaita-dark`. `nwg-look` may replace `gtk-4.0/gtk.css` with a symlink to a
theme — check before running `dotbackup`.

## Qt

`qt5ct.conf`/`qt6ct.conf` point `color_scheme_path` at
`qt*ct/colors/minimaru.conf` (an absolute path, stored as `@HOME@/…`). The icon
theme is named in four places — `gtk-3.0/settings.ini`, `gtk-4.0/settings.ini`,
`qt5ct.conf`, `qt6ct.conf` — and they must agree.
