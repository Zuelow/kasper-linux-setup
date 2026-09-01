# kasper-linux-setup

Post-install setup for Linux Mint, Debian, Fedora and Arch: Nordic/European
localisation plus a desktop theme (Windows 11/10, macOS, Arc, Nordic and more).

**Current version:** 4.2.0

### What's new in 4.2.0

Fixed a bug where a single dropped connection or a renamed/unreachable theme
repo (Fluent, WhiteSur, Orchis, Colloid, Graphite, Nordic, Windows-10,
ArcMenu) would silently kill the *entire* install partway through — including
every step still to come (menu button, panel layout, the final summary) —
instead of just skipping that one theme and continuing, which is what the
script's own messages already promised. `git clone` failures now retry a
couple of times and fall back to a warning instead of aborting the run.

## Usage

```bash
curl -fsSL https://kasper.sh/linux/install.sh | bash
```

Or with flags, e.g.:

```bash
bash install.sh --distro fedora --style win10 --panel
```

Run `install.sh --help` for the full list of options (distro, desktop,
language, keyboard, timezone, theme style, layout, menu button, dry-run, etc).

## What it does

- Sets language, keyboard layout and timezone in one go, matched to a chosen
  Nordic/European locale (Danish, Norwegian, Swedish, Finnish, German) or
  English.
- Installs and applies a desktop theme (Windows 11, Windows 10, macOS/WhiteSur,
  Arc, Orchis, Colloid, Graphite, Nordic, or the distro's own) across
  Cinnamon, GNOME, Xfce, MATE and (GTK-only) Plasma.
- Optionally reshapes the panel/taskbar into a classic, Windows 11-style, or
  macOS-style layout.
- Supports `--dry-run` to preview every change without touching the system,
  and `--yes` to skip all prompts.

## Contributors

- Kasper R. Zuelow
