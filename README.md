# hyprdecaffeine

A lightweight, robust suspend timer for Linux.

`hyprdecaffeine` is the opposite of the classic "Caffeine" utility. Instead of
keeping your computer awake, it allows you to easily schedule a system
suspension (sleep) after a specific amount of time. It features a fully-fledged
CLI backend and a clean, integrated Rofi GUI.

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

---

## 📦 Requirements

- **`systemd`**: For timer management and system suspension.
- **`rofi`**: For the graphical menu.
- **`libnotify`**: For `notify-send` desktop notifications.
- **Nerd Fonts**: (Optional but recommended) For the icons used in the Rofi menu
  and notifications.

---

## 🛠️ Installation

### Arch Linux (AUR)

```
paru -Syu hyprdecaffeine
```

---

## 🚀 Usage

`hyprdecaffeine` functions as both a CLI tool and a GUI launcher.

### Graphical Interface (Rofi)

To open the interactive menu, run:

```bash
hyprdecaffeine menu

```

### Command Line Interface

You can interact with the backend directly from your terminal or custom scripts:

```bash
# Start a timer (defaults to minutes if no unit is provided)
hyprdecaffeine start 15     # Suspends in 15 minutes
hyprdecaffeine start 45m    # Suspends in 45 minutes
hyprdecaffeine start 2h     # Suspends in 2 hours

# Check the status of a running timer
hyprdecaffeine status
#> 14m

# Cancel an active timer
hyprdecaffeine stop

```

---

## ⌨️ Hyprland Integration

To bind the Rofi menu to a keyboard shortcut in Hyprland, add the following to
your `~/.config/hypr/hyprland.conf`:

```conf
# Open the suspend timer menu with Super + Shift + S
bind = $mainMod SHIFT, S, exec, hyprdecaffeine menu

```

---

## 📝 License

This project is licensed under the MIT License.

