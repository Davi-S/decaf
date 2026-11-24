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
- **Firm, but safe.** It suspends even if your own programs hold locks against
  it (a download, expresso, a media server). It never overrides the locks of
  the system or of other users (a firmware update, a system upgrade): it tells
  you instead. Overriding your own locks asks for your password, unless you
  join the `decaf` group (see [Permissions](#permissions)).
- **Warns you.** "Suspending soon" appears a minute before, so you can cancel.
  On request, e.g. from a keybinding, `--notify` shows the timer's state, or
  that there was nothing to do.
- **Scriptable.** stdout is data only, errors go to stderr, and every outcome
  has its own exit status.

## Installation

### Arch Linux (AUR)

```bash
paru -S decaf
```

### From source

Dependencies: `bash`, `systemd`, `glib2` (for `gdbus`), `libnotify`, `polkit`,
and `make` to install.

```bash
git clone https://github.com/Davi-S/decaf.git
cd decaf
sudo make install              # installs to /usr/local; use PREFIX=/usr to change
sudo make uninstall            # to remove
```

`make install` also installs a polkit rule and creates the `decaf` group; see
[Permissions](#permissions).

### Permissions

When your own programs hold locks against sleep, suspending past them needs
your password: a prompt appears at the deadline, and if nobody answers within
25 seconds the system stays awake. To let a timer suspend while you are away,
join the `decaf` group:

```bash
sudo usermod -aG decaf "$USER"
```

The polkit rule shipped with decaf lets the group's members suspend past sleep
locks without a password, from an active local session. polkit can't tell
which program asks, so this applies to every program you run, not only decaf.
decaf itself still never suspends past the locks of the system or of other
users.

## Usage

```
decaf on DURATION [--notify]
decaf off [--notify]
decaf status [--notify]
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

`status --notify` prints the same, and also shows the state as a desktop
notification: "Decaf status: on" with `Suspending at 15:40 (29m left)`, or
"Decaf status: off" with `No timer is on`.

`on --notify` and `off --notify` also notify when there is nothing to do:
"Decaf status: already on" with the running timer, or "Decaf status: already
off". When they do something, the timer's own notification is enough.

The "status:" in the title tells these apart from the notifications sent when
a timer is really set or ends ("Decaf on", "Decaf off").

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

# Separate keys for on and off, notifying even when there is nothing to do
decaf on 1800 --notify
decaf off --notify

# Show the state, e.g. bound to a key
decaf status --notify >/dev/null

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
