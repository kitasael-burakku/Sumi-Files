# Versioning and releases

## Three version numbers

| What | Where the number lives | Tag |
|---|---|---|
| The repository (configuration + installer) | `VERSION`, `install.sh` (`VERSION=`) | `vX.Y.Z` |
| `dotbackup` | `bin/dotbackup` (`set -g VERSION`) | `dotbackup-vX.Y.Z` |
| `diskbackup` | `bin/diskbackup` (`set -g VERSION`) | `diskbackup-vX.Y.Z` |

The tools are versioned separately because they are distributed separately:
someone may copy `diskbackup` alone and needs to know when *its* behaviour
changed, independently of a new keybind.

All three follow [Semantic Versioning 2.0.0](https://semver.org/):

**Tools** — the public interface is the command line, the settings-file keys,
the manifest syntax and the exit codes.

- MAJOR: an option, key or exit code removed or changed in meaning; a default
  that makes an existing invocation write something different.
- MINOR: a new option, key, section or hook variable, backwards compatible.
- PATCH: bug fixes, messages, documentation.

**Repository** — the public interface is the manifest, the layout of
`config/`, the placeholders and the installer.

- MAJOR: a path moved or removed in `config/`, a manifest or placeholder
  change that breaks existing installs.
- MINOR: new configuration, new modules, new installer options.
- PATCH: fixes and tweaks to existing files.

Pre-1.0.0 (`0.y.z`) the repository may change more freely; the tools started
at 1.0.0 because their interface is already defined.

## Changelog

[`CHANGELOG.md`](../CHANGELOG.md) has one section per component (Repository,
dotbackup, diskbackup), newest version first, in
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) style. Work in
progress goes under `## [Unreleased]`. The test suite checks that each tool's
`--version` equals the first `## <tool> X.Y.Z` heading.

## Releasing

```bash
# 1. bump the number(s)
$EDITOR bin/dotbackup            # set -g VERSION 1.1.0
$EDITOR CHANGELOG.md             # move Unreleased entries under "## dotbackup 1.1.0 — <date>"

# 2. verify
tests/run.sh

# 3. commit and tag (annotated tags)
git commit -am "dotbackup 1.1.0"
git tag -a dotbackup-v1.1.0 -m "dotbackup 1.1.0"
git push origin main --follow-tags

# 4. publish (optional)
gh release create dotbackup-v1.1.0 --notes-from-tag bin/dotbackup
```

For a repository release, bump `VERSION` and `install.sh` together and tag
`vX.Y.Z`. Several components can be released in one commit with one tag each.

## Before the repository goes public

- `tests/run.sh privacy` passes (it reads your real `$USER`, `$HOME` and
  `~/.config/sumi-files/private-patterns` without ever storing them).
- `gitleaks git` over the full history passes.
- Re-check [THIRD_PARTY.md](../THIRD_PARTY.md) (anything listed under
  "Excluded until their origin is known").
- GitHub settings: description, topics, enable private vulnerability
  reporting, protect `main`.
