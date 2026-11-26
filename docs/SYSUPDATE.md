# sysupdate

Full system update for Arch Linux and its derivatives: pacman, an optional
AUR helper (yay or paru) and optional Flatpak. Before anything changes it
shows what is pending and checks for risks. After the update it verifies
the end state.

```
sysupdate                    preview → pacman → AUR → Flatpak → post-checks
sysupdate check              preview and risk check only; changes nothing
sysupdate -i 'qt6-*,qt6ct'   hold packages back (forwarded to pacman --ignore)
sysupdate --deep             add syumulation's ELF-level simulation to the preview
```

It is a single Python 3 file (standard library only; Python ≥ 3.11 to read
the settings file). It doesn't need fish, Hyprland or the rest of
Sumi-Files. `install.sh --with-tools` installs it into `~/.local/bin`, or you
can copy `bin/sysupdate` anywhere on your `PATH`.

## Why it exists

The exit code of `pacman -Syu` does not tell you whether the system is up to
date:

- pacman can drop a package with unresolvable dependencies, upgrade
  everything else and still exit 0;
- yay exits 1 both when you answer "no" and when a build fails;
- pkexec exits 126 when you dismiss the password dialog.

After each phase, sysupdate asks the package database what is still pending
(`pacman -Qu`, `<helper> -Qua`). It reads `pacman.log` to see what was
actually applied, and bases the verdict on those two answers.

## The preview and the risk check

The pending list comes from `checkupdates` (pacman-contrib), which syncs a
temporary database and never touches the real one. Without pacman-contrib,
or without network, it falls back to `pacman -Qu` and says so.

The **watch list** catches breakage that pacman cannot see. Some packages
use another package's private API: quickshell uses Qt's. When Qt changes
upstream version (6.12.0 → 6.12.1), the soname stays the same, so pacman
lets the upgrade through. If quickshell is not rebuilt in the same batch,
it then runs against a Qt it was not built for. sysupdate reports this case:

```
  ⚠ quickshell 0.3.2-1.1 would run against new versions it was not rebuilt for
      qt6-base 6.12.0-5 → 6.12.1-1, qt6-declarative …
  · Safe option: hold them back until the rebuild lands —
      sysupdate -i 'qt6-*,pyside6,qt6ct,shiboken6'
```

The suggested `--ignore` covers more than the watched globs. It adds every
pending package that is a rebuild against them: either its new version
depends on a held package, or it ships from the same PKGBUILD. pacman's own
resolver (`pacman -Sup`, a dry run) then checks that the rest of the upgrade
still resolves. At the prompt, `i` applies the suggestion.

A rebuild that only bumps the pkgrel (`6.12.0-5 → 6.12.0-6`) is not a risk.

`--deep` also runs `syumulation` when it is installed. syumulation is a
separate script, not part of Sumi-Files. It downloads the pending packages
and checks every ELF link and versioned symbol. It is slower, but it finds
linking breakage outside the watch list too.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Fully updated, nothing to flag |
| 10 | Updated with warnings: .pacnew files, orphans, reboot needed, processes running replaced code |
| 20 | Packages still pending (blocked, or held back) |
| 30 | Cancelled: declined at a prompt or authentication cancelled |
| 40 | Failed: pacman or the AUR helper failed, or a transaction stopped half-way |
| 1 | Could not start: no pacman, low disk space, database locked, declined at the first prompt |
| 2 | Bad arguments or settings |
| 130 | Interrupted (Ctrl+C) |

`sysupdate check` exits 0 (no risk), 10 (risks found) or 1 (could not check).
`sysupdate check --json` prints the pending packages, risks and suggestion
as JSON. `hypr/scripts/updates.sh` uses it to add a "Risky" line to the
update counter's tooltip and notification.

## Post-update checks

All of them are read-only:

- `.pacnew` / `.pacsave` files in `/etc`, `/boot` and every directory the
  package database lists as holding a backup file;
- orphaned packages, which are reported and never removed;
- whether a reboot is **required** (the running kernel's modules are gone)
  or **recommended** (the kernel, microcode, glibc, systemd, mesa, … were
  updated);
- Hyprland plugins invalidated by an ABI bump (hyprland, aquamarine,
  hyprutils, …). Rebuild them after restarting the session, because hyprpm
  builds against the running compositor;
- processes still executing a library or binary that the update replaced;
- tools installed outside pacman (cargo, pipx).

Without root, root-only paths and processes owned by other users cannot be
read. These blind spots are listed as information and don't change the
verdict. With `elevate = "sudo"`, the sudo timestamp from the pacman phase
lets the checks see everything.

At the end, sysupdate runs the `after` command. By default it starts
`updates-check.service`, if that unit exists, so the bar's update counter
refreshes right away.

## Settings

`~/.config/sysupdate/config.toml`. Start from
[`share/examples/sysupdate.toml`](../share/examples/sysupdate.toml), which
documents every key. An unknown key prints a warning; an invalid value is a
usage error (exit 2).

## What it never does

- It never forces anything (`-Rdd`, `--overwrite`, `-Sy` alone).
- It never removes the database lock. A stale lock gets the exact `rm`
  command, so you can run it yourself.
- It never removes orphans, merges .pacnew files or restarts services.
- It never runs as a background job. Every phase is interactive.
