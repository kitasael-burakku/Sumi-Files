# Fastfetch logos

Sumi-Files ships only the text logos it can license (`minimaru.txt`). These
presets expect files that are **not distributed** — third-party artwork, or
art whose origin couldn't be traced:

| Preset            | Expected file   |
|-------------------|-----------------|
| `goldship.jsonc`  | `goldship.png`  |
| `minimaru.jsonc`  | `minimaru.png`  |
| `yani.jsonc`      | `Yani-Neko.png` |
| `Yani-Neko.jsonc` | `Yani.png`      |
| `hyprmc.jsonc`    | `HyprMc.png`    |
| `fox.jsonc`       | `fox.txt` (text) |

Drop any file you have the rights to use here with the matching name.
Until then the `fastfetch` roulette in `fish/config.fish` skips those presets.
Image logos only render in terminals with the kitty graphics protocol; text
logos (`fox.txt`) work everywhere.
