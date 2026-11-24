# Third-party notices

Sumi-Files is MIT-licensed ([LICENSE](LICENSE)). It includes or configures
the following third-party work. Their licences apply to those files.

## Included code

| Files | Origin | Licence |
|---|---|---|
| `config/hypr/infinite_desktop/` (Python scripts and `system/` units) | [hyprland-infinitie-desktop-v2](https://github.com/sarodscommits/hyprland-infinitie-desktop-v2) by **sarodscommits** (Sarods2D), adapted (IPC layer `hypr_ipc.py`, socket-based input reader) | MIT — [`config/hypr/infinite_desktop/LICENSE`](config/hypr/infinite_desktop/LICENSE) |
| `config/cava/shaders/` (all shaders), `config/cava/config` layout | [cava](https://github.com/karlstav/cava) by **Karl Stavestrand**, as shipped in cava's `output/shaders/` | MIT — [`config/cava/shaders/LICENSE.cava`](config/cava/shaders/LICENSE.cava) |
| `config/cava/shaders/orion_*.frag` | **rezky_nightky**, contributed to cava (SPDX headers in each file) | MIT |
| Some `config/fastfetch/*.jsonc` presets | Adapted from [Fastfetch](https://github.com/fastfetch-cli/fastfetch) examples | MIT |

## Configured, not included

These projects are configured here; none of their code or binaries is in the
repository: Hyprland and `hyprpm`, Hyprlock, Hypridle,
[hypr-dynamic-cursors](https://github.com/VirtCode/hypr-dynamic-cursors) (VirtCode, MIT — `config/hypr/plugins/dym-cursor.lua`),
[matugen](https://github.com/InioX/matugen), Quickshell and Sumi Shell,
Kitty, Fish, Starship, Fastfetch, cava, qt5ct/qt6ct, mpvpaper, awww, cliphist,
udiskie.

## Removed on purpose

- `eye_of_phi.frag` (shipped by cava) is not included: its header says it was
  taken from Shadertoy user ChunderFPV, and Shadertoy's default licence
  (CC BY-NC-SA 3.0) is incompatible with this repository's MIT terms. Nothing
  here referenced it. If you want it, get it from cava.

## Excluded until their origin is known

- `fastfetch/fastfetchlogo/fox.txt` (braille fox used by `fox.jsonc`): no
  author or licence could be traced (none in the file, the preset or the
  history it came from), so it is not distributed. The preset stays; supply
  your own `fox.txt` to use it.

## Not distributed

Wallpapers, fastfetch image logos, icon/cursor themes and fonts are external
assets and are not part of this repository. See
[`config/fastfetch/fastfetchlogo/README.md`](config/fastfetch/fastfetchlogo/README.md)
and [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md).
