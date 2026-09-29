# Decaf

Suspend your Linux system after a while, from the command line or your scripts.

`decaf on 1800` suspends the system in 30 minutes. `decaf off` cancels it.
`decaf status` tells a script whether a timer is on and when it fires.
It is the opposite of [expresso](https://github.com/Davi-S/expresso), which
keeps the system awake for a while.

- **Native.** The timer is a transient systemd user unit; when it stops, for
  any reason, nothing is left behind.
- **Exact.** It fires at its wall-clock deadline, even across a suspend.
  If the system was already asleep at the deadline, it skips instead of
  suspending again as soon as you resume.
- **Firm.** It suspends even if other programs hold locks against it (a
  download, expresso). Overriding such a lock asks for your password; without
  one there is no prompt.
- **Warns you.** "Suspending soon" appears a minute before, so you can cancel.
- **Scriptable.** stdout is data only, errors go to stderr, and every outcome
  has its own exit status.

## Installation

### Arch Linux (AUR)

```bash
paru -S decaf
```

### From source

Dependencies: `bash`, `systemd`, `glib2` (for `gdbus`), `libnotify`, and `make`
to install.

```bash
git clone https://github.com/Davi-S/decaf.git
cd decaf
sudo make install              # installs to /usr/local; use PREFIX=/usr to change
sudo make uninstall            # to remove
```

## Usage

```
decaf on DURATION
decaf off
decaf status
```

`DURATION` is in seconds, 1 or more.

```bash
decaf on 2700                 # suspend in 45 minutes
decaf off
```

`status` prints `key=value` lines and exits 0 when a timer is on, 1 when not:

```console
$ decaf status
state=on
duration=2700
started=1759158600
until=1759161300
remaining=2412
$ decaf off && decaf status
state=off
```

### Exit status

| Code | Meaning |
|---|---|
| 0 | Success; for `status`, a timer is on |
| 1 | No timer is on (`status`, `off`) |
| 2 | Usage error |
| 3 | A timer is already on (`on`) |
| 4 | System error |

### Scripting

There is no configuration file: put your preferred durations in a keybinding,
alias or script.

```bash
# Toggle a 30-minute timer, e.g. bound to a key
decaf off 2>/dev/null || decaf on 1800

# When it fires
date -d "@$(decaf status | sed -n 's/^until=//p')"
```

See `man decaf` for the full reference, including how suspend, the warning and
other programs' locks behave.

## Development

- `make check` runs `shellcheck` and `shfmt`, and `make test` runs the test suite
  (needs `bats`: `pacman -S bash-bats`). CI runs both on every push.
- `make integration` tests against your real systemd session without
  suspending; run it before a release. `SUSPEND=1` adds checks that suspend
  the machine, each started only after you press Enter.
- The design and the reasons behind it are in [`docs/DESIGN.md`](docs/DESIGN.md).
- Record changes under `## [Unreleased]` in [`CHANGELOG.md`](CHANGELOG.md).
- Releases and AUR publishing are described in [`RELEASING.md`](RELEASING.md).

## License

[MIT](LICENSE)
