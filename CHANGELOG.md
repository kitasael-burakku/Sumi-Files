# Changelog

All notable changes to Sumi-Files. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The repository
and each tool are versioned separately — see [docs/RELEASING.md](docs/RELEASING.md).
The first heading of each section below is the current version; the test
suite checks it against `--version`.

## Repository

## [Unreleased]

### Added
- README: a hero screenshot and a gallery (`docs/screenshots/`, JPEG,
  1600×900, metadata stripped; user, host and location pixelated). The
  privacy test now allows images only as `docs/screenshots/*.jpg`.
- `docs/MIGRATING.md`: moving a machine that already has its own
  configuration to Sumi-Files, `dotbackup` and `diskbackup`; linked from the
  README and the other documents.
- `docs/DOTBACKUP.md` § Using your own repository: a fork or a new
  repository, the usual settings, what `dotbackup` doesn't do, and which
  protections depend on the repository's `hooks/`.
- `docs/CONFIGURATION.md`: top-level `hl.device` / `hl.env` calls in
  `private.lua` (and why they override the defaults), and the deliberate
  settings (lock xray, VRR, tearing, border).
- `docs/THEMING.md` § Window border: solid border, `borderangle` off.

### Changed
- Active window border is a solid accent colour in dynamic mode too (no
  gradient, no 45° angle), and the `borderangle` loop animation is off.
- `monitors.lua` uses `mode = "highrr"` instead of a fixed mode;
  `render.direct_scanout = 2` (auto, games only).
- Pointer acceleration is `flat` for every device (`input.lua`).
- Video players, OBS, Steam and games are always fully opaque.

### Removed
- `decoration.rounding_power` (no effect with `rounding = 0`).

### Fixed
- `decoration.lua`: the border fallback used when `hypr/colors.lua` is
  missing is the static accent (`rgba(90cececc)` / `rgba(90cece0f)`), as its
  comment says, instead of an older teal.
- `misc.lua` sets `vrr = 0` explicitly (VRR off on purpose) and notes that
  `session_lock_xray` is required.
- `.dotbackup-exclude` lists the generated colour files (`kitty/colors/colors.conf`,
  `hyprlock/colors.conf`, `hyprlock/scripts/music-colors.sh`, `hypr/colors.lua`,
  `hypr/dynamic-colors.sh`, `fish/conf.d/theme-goldship.fish`):
  `dotbackup --check` no longer reports drift right after installing, and they
  are no longer copied into the working tree.
- Test suite: the install tests copy only what git would publish, and the
  config shellcheck only checks those files, so ignored files in a working
  tree (generated colours, local completions) no longer make tests fail.
- Documentation now matches `--help` and the code: `install.sh
  --enable-services` also enables `dotbackup-remind.timer` when `dotbackup`
  is installed; `--with-tools` copies the tools and may write `repo =`;
  `--skip-colors` is listed; the monitor step no longer assumes a fixed mode;
  `dotbackup` exits 64 when it finds no repository, and the home-path check
  is only a warning with `--no-normalize-home`; `diskbackup --init` needs
  `--yes` off a terminal. "Differences from the original script" is
  condensed in `DOTBACKUP.md` and `DISKBACKUP.md`.

## 0.1.0 — 2026-11-24

### Added
- First release of Sumi-Files as an independent repository (no history
  inherited from the previous dotfiles).
- `config/` payload: Hyprland (Lua), systemd user units, Kitty, Fish,
  Hyprlock, matugen, GTK 3/4, Qt5/6, cava, fastfetch, Starship and the
  Sumi Shell preferences.
- `sumi-files.list`: one manifest shared by `install.sh`, `dotbackup` and
  `dotbackup-remind`.
- `install.sh`: optional, non-destructive installer (copy or symlink mode,
  backups of every replaced file, dry run).
- `.dotbackup-exclude` and `hooks/dotbackup/` (privacy, `Programs.*` guard,
  `KEYBINDS.txt` regeneration, template parity).
- `hooks/git/pre-commit`: privacy, secret and generated-file checks for every
  commit, enabled with `git config core.hooksPath hooks/git`.
- Test suite (`tests/run.sh`) and documentation under `docs/`.

### Changed
- Personal values (input devices, hostname, GPU driver, wallpaper, shell
  location/avatar, absolute home paths) replaced by defaults, examples or the
  `@HOME@` placeholder.

### Removed
- Private-project integration, legacy names and compatibility shims, image
  logos and screenshots, and the previous documentation.
- `eye_of_phi.frag` (Shadertoy-derived, licence incompatible with MIT).
- `fastfetch/fastfetchlogo/fox.txt` (origin and licence unknown; the
  `fox.jsonc` preset stays and works once you supply the file).

## dotbackup [Unreleased]

### Fixed
- The home-path check before committing no longer makes GNU grep ≥ 3.8 warn
  "stray \ before /": the path is escaped for ERE metacharacters only (and
  `#` only for the `sed` that normalises it).

## dotbackup 1.0.0 — 2026-11-24

### Added
- Command-line interface: `--source`, `--repo`, `--manifest`, `--payload`,
  `--config`, `--check`, `--dry-run`, `--yes`, `--interactive`, `--commit`,
  `--no-commit`, `--push`, `--message`, `--branch`, `--remote`,
  `--expect-remote`, `--exclude`, `--no-default-excludes`, `--no-delete`,
  `--no-snapshot`, `--keep`, `--snapshot-dir`, `--hooks-dir`,
  `--no-normalize-home`, `--skip-hooks`, `--quiet`, `--no-color`,
  `--help`, `--version`.
- Settings file `~/.config/sumi-files/dotbackup.conf` (parsed, never sourced).
- Manifest syntax with `src => dst` mappings and `~/` sources.
- Home-path normalisation (`@HOME@`) and a staged comparison shared by
  `--check`, `--dry-run` and the real run.
- Repository hooks, repository-owned excludes, documented exit codes.
- Symlink safety: links into the repository (`install.sh --link`) are never
  written through; stow-style folders and payload paths resolving outside the
  payload are refused; `.git` components and nested destinations are rejected.
- Owner-only snapshots.

### Changed
- Rewritten from the personal `dotbackup.fish`: no hardcoded repository,
  user name, remote or branch. Commit and push require explicit flags when
  not interactive. Requires rsync (the copy fallback could not mirror
  deletions). Prompts are in English.
- Project-specific checks moved to hooks.

## diskbackup [Unreleased]

### Fixed
- `--help` lists `--allow-system-disk`.

## diskbackup 1.0.0 — 2026-11-24

### Added
- Settings file `~/.config/sumi-files/diskbackup.conf` with `[general]`,
  `[repos]`, `[themes]`, `[files]`, `[dirs]`, `[state]` and `[snapshots]`.
- `--dest`, `--init` (destination marker), `--allow-system-disk`, `--dry-run`, `--only`,
  `--exclude`, `--no-delete`, `--require-mount`, `--no-require-mount`,
  `--yes`, `--interactive`, `--pause`, `--quiet`, `--no-color`, `--version`.
- Safety: writes only into a destination carrying `.diskbackup-target`,
  refuses `/`, `$HOME` and similar roots, refuses sources and destination
  that contain each other, refuses a group/world-writable settings file,
  refuses a destination on the system disk unless initialised for it,
  refuses to write through symlinks in the destination, owner-only output.

### Changed
- Rewritten from the personal `diskbackup` script: every path comes from the
  settings file. `--check` keeps its contract (0 up to date, 2 pending,
  pending lines start with `    + ` or `    ~ `); a missing settings file
  exits 66. The final "Press Enter" pause is now opt-in (`--pause`).
