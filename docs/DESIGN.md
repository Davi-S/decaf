# decaf 2.0 design

Ground-up rewrite. No backwards compatibility with 1.x; ships as 2.0.0.
decaf is expresso's opposite: expresso keeps the system awake for a while,
decaf suspends it after a while. Unless stated here, decaf follows expresso's
design (https://github.com/Davi-S/expresso/blob/main/docs/DESIGN.md), so the
two tools behave and are scripted the same way.
This file records decisions. Open items are listed at the end.

## Goals

- Bash only, minimal runtime dependencies: `bash`, `systemd`, `glib2` (for `gdbus`)
  and `libnotify`. 2.0 ships without the menu; `rofi` returns with it.
- Every feature is always on or doesn't exist (no optional dependencies).
- A strict, scriptable CLI. Users compose their own workflows with shell scripts.
- Fully testable in CI.

## CLI

```
decaf on DURATION
decaf off
decaf status
decaf --help
decaf --version
```

- **DURATION** is required: whole seconds, matching `^[1-9][0-9]*$`, at most
  `2147483647`. There is no `0`: to suspend now, use `systemctl suspend`.
- **No config file**, no options besides `--help` and `--version`.
- **stdout is data only; messages and errors go to stderr.**
- **The CLI never sends notifications.** The unit sends all of them.
- **`off` is synchronous:** when it returns, the timer is gone and `status` says off.
- A usage error prints `decaf: <problem>` and
  `Try 'decaf --help' for more information.` to stderr, and exits 2.

### Exit codes

Same meanings as expresso.

| Code | Meaning | Returned by |
|---|---|---|
| 0 | Success / timer is on | `on`, `off`, `status` (on), `--help`, `--version` |
| 1 | No timer running | `status` (off), `off` (nothing to turn off) |
| 2 | Usage error: bad command, option or duration | all |
| 3 | A timer is already running | `on` |
| 4 | System error: systemd call failed, no user manager | all |

### `status` output

`key=value` lines. Exit code 0 when on, 1 when off.

```
state=on              state=off
duration=1800
started=1759158600
until=1759160400
remaining=1740
```

- When on, all five keys are always present. `until` is when the system suspends.
- When off, the only line is `state=off`.

## Runtime model

A timer is **one transient systemd user unit**, `app-decaf.service` in `app.slice`,
started with `systemd-run --user --collect`. The unit is the whole state: if it is
running, a suspend is scheduled. Its values are unit environment variables
(`DECAF_STARTED`, `DECAF_DURATION`), read back by `status` with `systemctl show`.

```
decaf on 1800
   └─ systemd-run --user --unit=app-decaf --slice=app.slice --collect
        --setenv=DECAF_STARTED=… DECAF_DURATION=… -p ExecStopPost="decaf _stopped"
      └─ decaf _wait
            ├─ "Decaf on" notification
            ├─ waits for the deadline (wall clock, wakes on resume: see expresso)
            ├─ 60 s before, if awake: "Suspending soon" notification
            └─ at the deadline: suspend, or skip if the system was asleep then
      unit stops, for any reason → _stopped sends the matching notification
```

- **Deadline semantics.** `on N` means "at STARTED + N" on the wall clock; time
  spent suspended counts.
- **At the deadline, suspend is forced:** `systemctl suspend -i`, ignoring other
  programs' inhibitor locks (downloads, Steam, expresso). decaf wins over
  expresso: an explicit "sleep at 23:00" beats "stay awake".
- **Permission.** Verified: logind's `CanSuspend` answers `yes` from inside a user
  unit, so no password prompt. Overriding another user's *block* lock may still
  need authentication (polkit's `suspend-ignore-inhibit`); then the suspend fails
  and the "failed" notification says so.
- **Suspended before the deadline, resumed after it:** the timer is skipped, not
  suspended again on resume (the system was asleep at the deadline: the goal was
  met).
- **Suspended and resumed before the deadline:** the timer keeps its deadline.

### The waiter (`_wait`) at the end

The waiter is expresso's (deadline on the wall clock, `read -t` on a logind
monitor so it wakes within milliseconds of the deadline or of a resume), with
three additions:

- **Awake or asleep at the deadline.** While suspended, the waiter is frozen
  too; on resume it only sees that the deadline has passed. If it first sees
  the deadline more than 5 seconds late, the system was asleep then: skip.
  Otherwise suspend. (Awake, it always sees the deadline within a fraction of a
  second; 26 ms after resume was measured with expresso.) This also works in
  the fallback mode without the monitor.
- **The "Suspending soon" warning** is sent once, the first time the waiter is
  awake within the final 60 seconds: normally at deadline − 60 s, or right after
  a resume that lands inside that window. Not sent when DURATION ≤ 60.
- **Outcome, reported by exit code** for `_stopped` to pick the notification:

  | `_wait` result | Seen by `_stopped` as | Notification |
  |---|---|---|
  | exit 0: suspend requested | `exited` / `0` | none |
  | exit 10: skipped | `exited` / `10` | Skipped |
  | killed (`decaf off`) | `killed` / signal | Turned off |
  | anything else (e.g. the suspend was refused) | | Failed |

  The unit sets `SuccessExitStatus=10`, so a skipped timer is not logged as a
  failed unit.
- **Action:** suspend only (no hibernate or poweroff).
- Carried from expresso: install path check, one timer per user, concurrent `on`
  rejected by systemd, internal `_wait` / `_stopped` subcommands.

### Notifications

Sent only by the unit, with `notify-send --app-name=decaf`, normal urgency except
failures. Separate notifications, no replacing. Always English.

| Event | Title | Body | Shown for |
|---|---|---|---|
| Timer set | Decaf on | `Suspending at 23:00` (today) / `Suspending at Tue 09:00` (within 6 days) / `Suspending at 2025-10-29 15:10` | 2 s |
| 60 s before the deadline, if awake and DURATION > 60 | Suspending soon | `At 23:00 · run 'decaf off' to cancel` | 6 s |
| Suspended | (none: the screen goes off, and a notification waiting on resume would confuse) | | |
| Skipped | Decaf off | `Skipped: the system was asleep at 23:00` | 2 s |
| Turned off | Decaf off | `Turned off` | 2 s |
| Failed | Decaf failed | `Could not suspend. See: journalctl --user -u app-decaf` (critical) | 2 s |

## Code structure and testing

As in expresso: one file, `src/decaf`, in layers (cli → core → system → values),
discipline in place of types, bats with recording fakes (`systemd-run`,
`systemctl`, `date`, `gdbus`, `notify-send`, `sleep`), and a local
`tests/integration.sh` against the real systemd.

## Open

- The menu: designed after 2.0.
