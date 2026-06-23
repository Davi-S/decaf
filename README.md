# decaf

A lightweight, robust suspend timer for Linux.

`decaf` is the opposite of the classic "Caffeine" utility. Instead of keeping
your computer awake, it allows you to easily schedule a system suspension
(sleep) after a specific amount of time. It features a fully-fledged CLI backend
and a clean, integrated Rofi GUI.

### Features

- **OS-Native Timers:** Uses `systemd-run` transient monotonic timers. This
  guarantees exact durations, ignores system clock syncing discrepancies, and
  leaves zero background zombie processes.
- **Unconditional Suspend:** Bypasses active inhibitor locks (like playing
  videos or Steam downloads) to ensure the system _actually_ sleeps when you
  tell it to.
- **Integrated Frontend & Backend:** A single, clean Bash script manages both
  the CLI logic and the Rofi graphical interface.
- **Smart Notifications:** Native system notifications via `notify-send` for
  timer activation, cancellation, and errors.
- **Dynamic GUI:** The Rofi menu actively checks for running timers and
  dynamically injects a "Turn Off" option displaying the remaining time.

## Requirements

- **`systemd`**: For timer management and system suspension.
- **`rofi`**: For the graphical menu.
- **`libnotify`**: For `notify-send` desktop notifications.
- **Nerd Fonts**: (Optional but recommended) For the icons used in the Rofi menu
  and notifications.

## Installation

### Arch Linux (AUR)

```bash
paru -Syu decaf
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

