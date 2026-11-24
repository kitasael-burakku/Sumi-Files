# Changelog

All notable changes to Sumi-Files. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The repository
and each tool are versioned separately — see [docs/RELEASING.md](docs/RELEASING.md).
The first heading of each section below is the current version; the test
suite checks it against `--version`.

## Repository

## [Unreleased]

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
