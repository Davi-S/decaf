# Decaf

A lightweight, robust suspend timer for Linux.

`decaf` is the opposite of the classic "Caffeine" utility. Instead of keeping
your computer awake, it allows you to easily schedule a system suspension
(sleep) after a specific amount of time. It features a fully-fledged CLI backend
and a clean, integrated Rofi GUI.

### Features

- **OS-Native Timers:** Uses `systemd-run` transient wall-clock timers (`--on-calendar`).
  This accounts for system suspend/sleep periods, ensures absolute expiration, and
  leaves zero background zombie processes.
- **Unconditional Suspend:** Bypasses active inhibitor locks (like playing
  videos or Steam downloads) to ensure the system _actually_ sleeps when you
  tell it to.
- **Integrated Frontend & Backend:** A single, clean Bash script manages both
  the CLI logic and the Rofi graphical interface.
- **Smart Notifications:** Native system notifications via `notify-send` for
  timer activation, cancellation, and errors.

## Requirements

- **`systemd`**: For timer management and system suspension.
- **`rofi`**: For the graphical menu.
- **`libnotify`**: For `notify-send` desktop notifications.

## Installation

### Arch Linux (AUR)

```bash
paru -S decaf
```

### From source

Dependencies: `bash`, `systemd`, `rofi`, `libnotify`, `make`.

```bash
git clone https://github.com/Davi-S/decaf.git
cd decaf
sudo make install              # installs to /usr/local; use PREFIX=/usr to change
sudo make uninstall            # to remove
```

## Usage

`decaf` functions as both a CLI tool and a GUI launcher.

### Graphical Interface (Rofi)

To open the interactive menu, run:

```bash
decaf menu
```

### Command Line Interface

You can interact with the backend directly from your terminal or custom scripts:

```bash
# Start a timer (defaults to minutes if no unit is provided)
decaf start 15     # Suspends in 15 minutes
decaf start 45m    # Suspends in 45 minutes
decaf start 2h     # Suspends in 2 hours

# Check the status of a running timer
decaf status
#> 14m

# Cancel an active timer
decaf stop
```

See `man decaf` for the full reference.

## Development

- `make check` runs `shellcheck` and `shfmt`, and `make test` runs the test suite
  (needs `bats`: `pacman -S bash-bats`). CI runs both on every push.
- `make integration` tests against your real systemd session without
  suspending; run it before a release. `SUSPEND=1` adds checks that suspend
  the machine, each started only after you press Enter.
- Record changes under `## [Unreleased]` in [`CHANGELOG.md`](CHANGELOG.md).
- Releases and AUR publishing are described in [`RELEASING.md`](RELEASING.md).

## License

[MIT](LICENSE)

